# state（Terraform が作ったものの記録）の保存先。インフラ設計書 12.4、手順書 5.。
#
# バケット名はアカウントごとに違う（inquirymanagement-tfstate-<アカウント ID>）ため、ここには書かず、
# init のときに渡す。
#   terraform -chdir=infra/terraform init -backend-config="bucket=inquirymanagement-tfstate-<アカウント ID>"
# スクリプト（infra/scripts/）は、未初期化なら自動でこのコマンドを実行する。

terraform {
  backend "s3" {
    key          = "prod/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true # S3 上にロック用のファイルを置き、同時に 2 か所から apply できないようにする
  }
}
