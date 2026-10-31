#!/usr/bin/env bash
# 休止する（すべて撤去する）。データは DB のスナップショットで次の再開に引き継ぐ（手順書 7.2）。
#   bash infra/scripts/shutdown.sh          撤去するものを表示し、確認してから実行する
#   bash infra/scripts/shutdown.sh --yes    確認を省略する（内容を確認済みのとき）
#
# 1. terraform plan -destroy で、撤去するものの一覧を表示する → 確認
# 2. RDS のスナップショットを日時入りの名前で取り、完成を待つ（完成しなければ何も消さずに中止）
# 3. 最新の 2 つより古いスナップショットを消す
# 4. 保存した計画で terraform destroy を実行する
# 5. Terraform が管理するものが何も残っていないことを確かめる

source "$(dirname "$0")/lib.sh"

usage() { sed -n '2,11p' "$0"; }
parse_common_args "$@"

show_identity
ensure_init

if [ -z "$(tf state list 2>/dev/null)" ]; then
  step "既に休止中です（Terraform が管理するリソースはありません）"
  exit 0
fi

# --- 1. 撤去するものの確認 ---
step "撤去するものの確認（terraform plan -destroy）"
tf plan -destroy -input=false -out=tfplan-destroy >/dev/null
show_plan_summary tfplan-destroy
info "EC2・RDS・CloudFront・ECR（イメージを含む）・パラメータ・ログをすべて撤去します。"
info "撤去後は、DB のスナップショットと state 用のバケットだけが残ります（費用はほぼ 0 ドル）。"
info "再開すると URL が変わります。"
confirm "スナップショットを取ってから、すべて撤去しますか？"

# --- 2・3. スナップショット ---
if db_exists; then
  SNAPSHOT_ID="${PROJECT}-$(date +%Y%m%d-%H%M)"
  step "スナップショットを作成（${SNAPSHOT_ID}）。完成まで数分かかります"
  aws rds create-db-snapshot \
    --db-instance-identifier "${PROJECT}" \
    --db-snapshot-identifier "${SNAPSHOT_ID}" \
    --query 'DBSnapshot.Status' --output text
  aws rds wait db-snapshot-available --db-snapshot-identifier "${SNAPSHOT_ID}" \
    || die "スナップショットが完成しませんでした。データを失わないよう、何も撤去せずに中止しました。"
  info "完成しました"

  step "古いスナップショットを削除（最新の 2 つを残す）"
  mapfile -t SNAPSHOTS < <(list_snapshots_oldest_first)
  if [ "${#SNAPSHOTS[@]}" -gt 2 ]; then
    for old in "${SNAPSHOTS[@]:0:${#SNAPSHOTS[@]}-2}"; do
      aws rds delete-db-snapshot --db-snapshot-identifier "${old}" --query 'DBSnapshot.DBSnapshotIdentifier' --output text
    done
  else
    info "削除するものはありません"
  fi
else
  info "DB が無いため、スナップショットは取りません"
fi

# --- 4. 撤去 ---
step "terraform destroy（CloudFront の削除に時間がかかります。15〜25 分）"
tf apply -input=false tfplan-destroy \
  || die "撤去が途中で失敗しました。数分待ってから、もう一度 shutdown.sh を実行してください（手順書 9.5）。"
rm -f "${TF_DIR}/tfplan-destroy"

# --- 5. 確認 ---
REMAINING="$(tf state list)"
if [ -n "${REMAINING}" ]; then
  printf '%s\n' "${REMAINING}"
  die "上のリソースが残っています。もう一度 shutdown.sh を実行してください。"
fi
step "休止しました（Terraform が管理するリソースはすべて撤去済み）"
info "残っているスナップショット:"
list_snapshots_oldest_first | sed 's/^/      /'
info "再開するときは bash infra/scripts/startup.sh を実行してください。"
