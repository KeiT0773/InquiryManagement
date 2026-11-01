#!/usr/bin/env bash
# 休止から再開する（すべて作り直す）。初回の構築にも使う（手順書 6.1・7.3）。
#   bash infra/scripts/startup.sh          内容を表示し、確認してから構築する
#   bash infra/scripts/startup.sh --yes    確認を省略する（内容を確認済みのとき）
#
# 1. 最新のスナップショットを探し、terraform.tfvars の db_snapshot_identifier に書く（無ければ DB を新規作成）
# 2. 作られるものを表示して確認を求める
# 3. ECR だけを先に作る
# 4. 今のコミットの backend・web イメージを作って ECR に登録する
# 5. terraform plan → apply（RDS の作り直しなど、想定外の削除が含まれていたら中止）
# 6. EC2 がコンテナを起動するのを待ち、CloudFront の URL で画面と API を確かめる（URL は再開のたびに変わる）
#
# 稼働中は約 0.05 ドル / 時間かかる。使い終わったら shutdown.sh で休止する。

source "$(dirname "$0")/lib.sh"

usage() { sed -n '2,14p' "$0"; }
parse_common_args "$@"

show_identity
require_docker
require_clean backend frontend
ensure_init

if db_exists; then
  die "アプリは既に稼働しています。更新は deploy-backend.sh / deploy-frontend.sh で行ってください。"
fi

# --- 1. 復元するスナップショット ---
step "復元に使うスナップショットを探す"
SNAPSHOT="$(list_snapshots_oldest_first | tail -n 1)"
if [ -n "${SNAPSHOT}" ]; then
  info "最新のスナップショット: ${SNAPSHOT}（休止前の問い合わせが戻ります）"
else
  info "スナップショットがありません。DB を新規に作ります（問い合わせは空から始まります）"
fi
set_tfvar db_snapshot_identifier "${SNAPSHOT}"

# --- 2. 確認の前に、作られるものの一覧を表示する ---
step "作成されるリソースの確認（イメージのタグは仮の値で計算）"
tf plan -input=false -var "backend_image_tag=preview" -var "web_image_tag=preview" -out=tfplan-preview >/dev/null
show_plan_summary tfplan-preview
check_destroys tfplan-preview
rm -f "${TF_DIR}/tfplan-preview"
info "稼働中は約 0.05 ドル / 時間かかります（インフラ設計書 11.）。構築には 20〜30 分かかります。"

confirm "再開（構築）しますか？"

# --- 3. ECR ---
step "ECR を作成"
tf apply -input=false -auto-approve -target=aws_ecr_repository.app -target=aws_ecr_lifecycle_policy.app

# --- 4. イメージ ---
build_and_push_image backend
build_and_push_image web

# --- 5. 全体の構築 ---
step "terraform plan"
tf plan -input=false -out=tfplan
show_plan_summary tfplan
check_destroys tfplan
step "terraform apply（RDS と CloudFront の作成に時間がかかります）"
tf apply -input=false tfplan
rm -f "${TF_DIR}/tfplan"

# --- 6. 確認（EC2 は起動時に start.sh でコンテナを起動する。新規の DB ではテーブルの作成も行う） ---
verify_app

step "再開しました"
info "URL: $(tf output -raw app_url)"
info "使い終わったら、bash infra/scripts/shutdown.sh で休止してください（稼働中は約 0.05 ドル / 時間）。"
