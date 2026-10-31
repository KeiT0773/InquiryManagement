#!/usr/bin/env bash
# バックエンド（Rails）を更新する（手順書 6.2）。稼働中にだけ使う。
#   bash infra/scripts/deploy-backend.sh          計画を表示し、確認してから適用する
#   bash infra/scripts/deploy-backend.sh --yes    確認を省略する（計画を確認済みのとき）
#
# 1. 今のコミットの backend イメージを作って ECR に登録する
# 2. terraform.tfvars の backend_image_tag を書き換え、plan（タグのパラメータの更新だけのはず）→ 確認 → apply
# 3. EC2 で start.sh を実行し、新しいイメージに入れ替える（マイグレーションがあれば起動時に適用される）
# 4. CloudFront の URL で画面と API を確かめる

source "$(dirname "$0")/lib.sh"

usage() { sed -n '2,10p' "$0"; }
parse_common_args "$@"

show_identity
require_docker
require_clean backend
ensure_init
db_exists || die "アプリが稼働していません（休止中）。再開は bash infra/scripts/startup.sh で行ってください。"

build_and_push_image backend

step "terraform plan"
tf plan -input=false -out=tfplan
show_plan_summary tfplan
check_destroys tfplan

confirm "この計画を適用し、EC2 のバックエンドを入れ替えますか？"
step "terraform apply"
tf apply -input=false tfplan
rm -f "${TF_DIR}/tfplan"

run_start_on_ec2
verify_app
step "バックエンドの更新が終わりました（イメージ: $(git -C "${REPO_ROOT}" rev-parse --short HEAD)）"
info "URL: $(tf output -raw app_url)"
