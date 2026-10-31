#!/usr/bin/env bash
# 画面を更新する（手順書 6.3）。稼働中にだけ使う。
#   bash infra/scripts/deploy-frontend.sh          計画を表示し、確認してから適用する
#   bash infra/scripts/deploy-frontend.sh --yes    確認を省略する（計画を確認済みのとき）
#
# 1. frontend で npm run build を実行し、今のコミットの web イメージ（nginx + 画面）を作って ECR に登録する
# 2. terraform.tfvars の web_image_tag を書き換え、plan（タグのパラメータの更新だけのはず）→ 確認 → apply
# 3. EC2 で start.sh を実行し、新しいイメージに入れ替える
# 4. CloudFront のキャッシュを無効化し、画面と API を確かめる

source "$(dirname "$0")/lib.sh"

usage() { sed -n '2,10p' "$0"; }
parse_common_args "$@"

show_identity
require_docker
require_clean frontend infra/docker/web
ensure_init
db_exists || die "アプリが稼働していません（休止中）。再開は bash infra/scripts/startup.sh で行ってください。"

build_and_push_image web

step "terraform plan"
tf plan -input=false -out=tfplan
show_plan_summary tfplan
check_destroys tfplan

confirm "この計画を適用し、EC2 の画面を入れ替えますか？"
step "terraform apply"
tf apply -input=false tfplan
rm -f "${TF_DIR}/tfplan"

run_start_on_ec2
invalidate_cache
verify_app
step "画面の更新が終わりました（イメージ: $(git -C "${REPO_ROOT}" rev-parse --short HEAD)。反映まで 1〜2 分かかることがあります）"
info "URL: $(tf output -raw app_url)"
