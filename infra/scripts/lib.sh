#!/usr/bin/env bash
# infra/scripts/*.sh が共通で使う関数。直接は実行しない（source で読み込む）。
# Git Bash で、リポジトリのルートから実行する前提（手順書 1.2）。

set -euo pipefail

# --- 場所 -------------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="${REPO_ROOT}/infra/terraform"
TFVARS="${TF_DIR}/terraform.tfvars"
PROJECT="inquirymanagement"
REGION="ap-northeast-1"
APP_DIR="/opt/${PROJECT}"
export AWS_REGION="${REGION}"

# --- 表示 -------------------------------------------------------------------------
step() { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\n[中止] %s\n' "$*" >&2; exit 1; }

tf() { terraform -chdir="${TF_DIR}" "$@"; }

# --- オプション -------------------------------------------------------------------
# --yes：確認を省略する。Claude が実行するときは、利用者が承認したあとにだけ付ける（手順書 8.）。
ASSUME_YES=false
parse_common_args() {
  for arg in "$@"; do
    case "$arg" in
      --yes|-y) ASSUME_YES=true ;;
      -h|--help) usage; exit 0 ;;
      *) die "不明なオプション: $arg" ;;
    esac
  done
}

# 確認を求める。--yes があれば省略。端末から入力できない（Claude などが実行している）ときは中止する。
confirm() {
  local message="$1"
  if [ "$ASSUME_YES" = true ]; then
    info "（--yes が指定されているため、確認を省略）"
    return 0
  fi
  if [ ! -t 0 ]; then
    die "確認の入力ができないため、ここで止めました。内容を確認したうえで --yes を付けて実行し直してください。"
  fi
  local answer
  read -r -p "${message} [y/N] " answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) die "中止しました（ここまでに表示した操作のほかは、何も変更していません）。" ;;
  esac
}

# --- 事前の確認 -------------------------------------------------------------------
# 誰として、どのアカウントを操作するかを表示する（手順書 4.2、8.）
show_identity() {
  step "AWS の認証を確認"
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)" \
    || die "AWS に接続できません。aws configure の設定を確認してください（手順書 4.2）。"
  info "アカウント: ${ACCOUNT_ID}"
  info "操作する人: $(aws sts get-caller-identity --query Arn --output text)"
  STATE_BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"
}

require_docker() {
  docker info >/dev/null 2>&1 || die "Docker が起動していません。Docker Desktop を起動してから実行してください。"
}

# イメージのタグ（コミットハッシュ）と中身を一致させるため、コミットしていない変更があれば止める（12.3）
require_clean() {
  local dir
  for dir in "$@"; do
    if [ -n "$(git -C "${REPO_ROOT}" status --porcelain -- "${dir}")" ]; then
      die "${dir}/ にコミットしていない変更があります。イメージのタグ（コミットハッシュ）と中身が食い違うため、コミットしてから実行してください。"
    fi
  done
}

# Terraform が state の保存先（S3）に接続済みか確かめ、未接続なら init する（手順書 6.1）
ensure_init() {
  if [ ! -f "${TF_DIR}/.terraform/terraform.tfstate" ]; then
    aws s3api head-bucket --bucket "${STATE_BUCKET}" >/dev/null 2>&1 \
      || die "state の保存先のバケット ${STATE_BUCKET} がありません。手順書 5. の手順で作ってください。"
    step "terraform init（state の保存先: ${STATE_BUCKET}）"
    tf init -input=false -reconfigure -backend-config="bucket=${STATE_BUCKET}"
  fi
}

# terraform.tfvars が無ければ記入例から作る
ensure_tfvars() {
  if [ ! -f "${TFVARS}" ]; then
    cp "${TF_DIR}/terraform.tfvars.example" "${TFVARS}"
    info "terraform.tfvars を記入例から作成しました"
  fi
}

# terraform.tfvars の 1 項目を書き換える（無ければ末尾に追加）。
# set_tfvar は文字列として（"..." で囲んで）、set_tfvar_raw は値をそのまま（リストなど）書く。
set_tfvar_raw() {
  local key="$1" value="$2"
  ensure_tfvars
  if grep -qE "^${key}[[:space:]]*=" "${TFVARS}"; then
    sed -i "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "${TFVARS}"
  else
    printf '%s = %s\n' "${key}" "${value}" >> "${TFVARS}"
  fi
  info "terraform.tfvars: ${key} = ${value}"
}

set_tfvar() {
  set_tfvar_raw "$1" "\"$2\""
}

# --- 計画の検査（12.3） -------------------------------------------------------------
# 保存した計画（tfplan）の集計を表示する
show_plan_summary() {
  local plan_file="$1"
  tf show -no-color "${plan_file}" | grep -E '^(Plan:|No changes)' || true
}

# 計画に「削除」や「作り直し」が含まれていないか調べる。
#   - RDS（aws_db_instance）の削除・作り直しは、常に中止する（データが消えるため）
#   - EC2（aws_instance.app）の作り直しは、user_data を変えたときの正常な動き（7.2）。内容を表示して確認を求める
#   - それ以外の削除・作り直しは中止する
check_destroys() {
  local plan_file="$1" offending others
  # 計画の中の「# <リソース> will be destroyed / must be replaced」の行を集める
  offending="$(tf show -no-color "${plan_file}" | grep -E '^  # .* (will be destroyed|must be replaced)' || true)"
  [ -n "${offending}" ] || return 0

  printf '%s\n' "${offending}" >&2
  if printf '%s\n' "${offending}" | grep -q '^  # aws_db_instance\.'; then
    die "計画に DB（RDS）の削除・作り直しが含まれています（上の一覧）。データが消えるため中止しました。"
  fi
  others="$(printf '%s\n' "${offending}" | grep -v '^  # aws_instance\.app ' || true)"
  if [ -n "${others}" ]; then
    die "計画に想定外の削除・作り直しが含まれています（上の一覧）。中止しました。"
  fi
  info "EC2 を作り直します（user_data の変更など。データは RDS にあるため失われません。URL は変わりません）。"
  confirm "EC2 の作り直しを含めて続けますか？"
}

# --- イメージ ---------------------------------------------------------------------
# ECR のアドレス。ECR だけを先に作った直後（-target）は terraform output に値が無いことがあるため、
# AWS から直接読む。
ecr_url() {
  aws ecr describe-repositories --repository-names "${PROJECT}-$1" \
    --query 'repositories[0].repositoryUri' --output text
}

ecr_login() {
  local url; url="$(ecr_url backend)"
  aws ecr get-login-password --region "${REGION}" \
    | docker login --username AWS --password-stdin "${url%%/*}" >/dev/null
}

# 今のコミットのイメージを作って ECR に登録し、terraform.tfvars のタグを書き換える（7.4）。
# 同じタグが登録済みなら作り直さない（ECR はタグの上書きを禁止しているため）。
#   $1：backend または web
build_and_push_image() {
  local name="$1" tag url
  require_docker
  tag="$(git -C "${REPO_ROOT}" rev-parse --short HEAD)"
  url="$(ecr_url "${name}")"

  if aws ecr describe-images --repository-name "${PROJECT}-${name}" --image-ids imageTag="${tag}" >/dev/null 2>&1; then
    step "${name} イメージ ${tag} は ECR に登録済みのため、作成を省略"
  else
    step "${name} イメージを作成して ECR に登録（タグ: ${tag}）"
    ecr_login
    if [ "${name}" = backend ]; then
      docker build --platform linux/amd64 -t "${url}:${tag}" "${REPO_ROOT}/backend"
    else
      # 本番は画面と同じドメインの /api を呼ぶ（.env.production の NEXT_PUBLIC_API_BASE_URL は空）
      (
        cd "${REPO_ROOT}/frontend"
        [ -d node_modules ] || npm ci
        npm run build
      )
      docker build --platform linux/amd64 --build-context site="${REPO_ROOT}/frontend/out" \
        -t "${url}:${tag}" "${REPO_ROOT}/infra/docker/web"
    fi
    docker push "${url}:${tag}"
  fi
  set_tfvar "${name}_image_tag" "${tag}"
}

# --- EC2 --------------------------------------------------------------------------
# EC2 で start.sh を実行する（SSM Run Command。7.4）。新しいタグのイメージを取得して入れ替え、
# backend の /up が 200 になるまで待つ。失敗したら、EC2 の出力を表示して中止する。
run_start_on_ec2() {
  local instance_id command_id status
  instance_id="$(tf output -raw instance_id)"
  step "EC2（${instance_id}）でコンテナを入れ替える（start.sh。数分かかります）"
  command_id="$(MSYS_NO_PATHCONV=1 aws ssm send-command --instance-ids "${instance_id}" \
    --document-name AWS-RunShellScript --comment "${PROJECT} deploy" --timeout-seconds 600 \
    --parameters "commands=[\"${APP_DIR}/start.sh\"]" --query Command.CommandId --output text)"

  for _ in $(seq 1 120); do
    status="$(aws ssm get-command-invocation --command-id "${command_id}" --instance-id "${instance_id}" \
      --query Status --output text 2>/dev/null || echo Pending)"
    case "${status}" in
      Pending|InProgress|Delayed) sleep 5 ;;
      *) break ;;
    esac
  done
  aws ssm get-command-invocation --command-id "${command_id}" --instance-id "${instance_id}" \
    --query '[StandardOutputContent, StandardErrorContent]' --output text | tail -n 15 | sed 's/^/      /'
  [ "${status}" = Success ] || die "EC2 での入れ替えが ${status} で終わりました。上の出力と、手順書 9.1 のログを確認してください。"
}

# CloudFront の URL で画面と API を確かめる（12.3）
verify_app() {
  local url
  url="$(tf output -raw app_url)"
  step "動作確認（${url}）"
  curl -fsS -o /dev/null -m 20 --retry 40 --retry-delay 15 --retry-all-errors "${url}/"     || die "画面が応答しません。手順書 9.2 を確認してください。"
  info "画面：200"
  curl -fsS -o /dev/null -m 20 --retry 20 --retry-delay 15 --retry-all-errors "${url}/api/lists"     || die "API が応答しません。手順書 9.2 を確認してください。"
  info "API（/api/lists）：200"
}

invalidate_cache() {
  local dist_id
  dist_id="$(tf output -raw cloudfront_distribution_id)"
  step "CloudFront のキャッシュを無効化"
  MSYS_NO_PATHCONV=1 aws cloudfront create-invalidation --distribution-id "${dist_id}" --paths "/*" \
    --query 'Invalidation.[Id,Status]' --output text
}

# --- その他 -----------------------------------------------------------------------
db_exists() {
  aws rds describe-db-instances --db-instance-identifier "${PROJECT}" >/dev/null 2>&1
}

# スナップショット（inquirymanagement-YYYYMMDD-HHMM）を古い順に 1 行ずつ出力する
list_snapshots_oldest_first() {
  aws rds describe-db-snapshots --snapshot-type manual \
    --query "sort_by(DBSnapshots[?starts_with(DBSnapshotIdentifier, '${PROJECT}-') && Status=='available'], &SnapshotCreateTime)[].DBSnapshotIdentifier" \
    --output text | tr '\t' '\n' | sed '/^$/d;/^None$/d'
}
