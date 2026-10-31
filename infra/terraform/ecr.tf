# イメージの置き場所（ECR）。backend（Rails）と web（nginx + 画面）の 2 つ。インフラ設計書 4.・7.4。
# 初回と再開時は、この 2 つだけを先に作ってからイメージを登録する（手順書 6.1）。

locals {
  ecr_repositories = toset(["backend", "web"])
}

resource "aws_ecr_repository" "app" {
  for_each = local.ecr_repositories

  name = "${var.project}-${each.key}"

  # 同じタグでの上書きを禁止する。タグ（コミットハッシュ）とイメージの中身を常に一致させるため。
  image_tag_mutability = "IMMUTABLE"

  # 休止（terraform destroy）のとき、イメージが残っていても消せるようにする。
  force_delete = true

  # 登録時の脆弱性の簡易検査（基本スキャン。無料）。
  image_scanning_configuration {
    scan_on_push = true
  }
}

# 古いイメージを自動で消す。新しい順に 5 つだけ残す（インフラ設計書 7.4）。
resource "aws_ecr_lifecycle_policy" "app" {
  for_each = aws_ecr_repository.app

  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep only the 5 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}
