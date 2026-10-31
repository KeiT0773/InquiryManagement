#!/usr/bin/env bash
# 稼働中に自宅の IPv6 のネットワーク番号が変わったとき、アクセスの許可リストだけを更新する（手順書 6.5）。
#   bash infra/scripts/update-allowed-ip.sh          計画を表示し、確認してから適用する
#   bash infra/scripts/update-allowed-ip.sh --yes    確認を省略する（計画を確認済みのとき）
#
# 1. この PC の IPv6 アドレスを調べ、先頭 64 ビットを terraform.tfvars の allowed_viewer_ipv6_prefixes に書く
# 2. terraform plan（CloudFront Functions の関数の更新だけであることを確かめる）→ 確認 → apply
#
# 休止中は不要（再開の startup.sh が自動で今のネットワーク番号を使う）。

source "$(dirname "$0")/lib.sh"

usage() { sed -n '2,9p' "$0"; }
parse_common_args "$@"

show_identity
ensure_init
tf state list 2>/dev/null | grep -q '^aws_cloudfront_function\.viewer_allowlist$' \
  || die "アプリが稼働していません（休止中）。再開の startup.sh が、自動で今のネットワーク番号を使います。"

configure_allowlist

step "terraform plan"
tf plan -input=false -out=tfplan-allowlist >/dev/null
show_plan_summary tfplan-allowlist
if tf show -no-color tfplan-allowlist | grep -q '^No changes'; then
  rm -f "${TF_DIR}/tfplan-allowlist"
  step "許可リストは今のネットワーク番号と同じです（変更なし）"
  exit 0
fi

# 関数の更新以外（ほかのリソースの変更・削除・作り直し）が含まれていたら止める
OTHERS="$(tf show -no-color tfplan-allowlist | grep -E '^  # .* (will be|must be)' \
  | grep -v '^  # aws_cloudfront_function\.viewer_allowlist will be updated' || true)"
if [ -n "${OTHERS}" ]; then
  printf '%s\n' "${OTHERS}" >&2
  die "許可リスト以外の変更が含まれています（上の一覧）。deploy-*.sh など、目的に合った方法で適用してください。"
fi

confirm "許可リストを ${ALLOWED_PREFIX} に更新しますか？"
step "terraform apply"
tf apply -input=false tfplan-allowlist
rm -f "${TF_DIR}/tfplan-allowlist"

step "許可リストを更新しました（CloudFront の全拠点に反映されるまで数分かかります）"
info "URL: $(tf output -raw app_url)"
