# 秘密情報と、動かすイメージのタグ（SSM パラメータストア）。インフラ設計書 7.4・9.。
# 保管先は無料の標準パラメータ（有料の Secrets Manager は使わない）。
# 値は EC2 の start.sh が起動のたびに読む。user_data・compose.yaml にはパラメータの名前だけを書く。
# 休止（destroy）でパラメータも消え、再開のたびに新しい秘密の値が生成される。

# --- 秘密の値の生成（英数字だけ。環境変数や nginx の設定に書いても記号で壊れないように） ---
resource "random_password" "db" {
  length  = 32
  special = false
}

resource "random_password" "secret_key_base" {
  length  = 64
  special = false
}

resource "random_password" "origin_verify" {
  length  = 32
  special = false
}

locals {
  # パラメータの名前 → 値。SecureString は AWS 管理の鍵（aws/ssm）で暗号化される
  secure_parameters = {
    "db-password"     = random_password.db.result              # RDS のマスターパスワード（rds.tf）
    "secret-key-base" = random_password.secret_key_base.result # Rails の SECRET_KEY_BASE
    "origin-verify"   = random_password.origin_verify.result   # CloudFront → nginx の確認用ヘッダー（6.2）
  }
}

resource "aws_ssm_parameter" "secure" {
  for_each = local.secure_parameters

  name  = "/${var.project}/${each.key}"
  type  = "SecureString"
  tier  = "Standard"
  value = each.value
}

# --- 動かすイメージのタグ（7.4） ---
# デプロイのスクリプトがタグを書き換えて apply し、EC2 の start.sh を実行する。EC2 は作り直さない。
resource "aws_ssm_parameter" "image_tag" {
  for_each = {
    "backend-image-tag" = var.backend_image_tag
    "web-image-tag"     = var.web_image_tag
  }

  name  = "/${var.project}/${each.key}"
  type  = "String"
  tier  = "Standard"
  value = each.value

  lifecycle {
    precondition {
      condition     = each.value != ""
      error_message = "イメージのタグ（backend_image_tag / web_image_tag）が空です。startup.sh か deploy-*.sh を使ってください。スクリプトがイメージを ECR に登録してからタグを書きます（手順書 6.）。"
    }
  }
}
