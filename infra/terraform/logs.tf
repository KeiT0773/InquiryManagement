# コンテナのログ（標準出力）の保管場所。Docker の awslogs ログドライバーが書き込む。インフラ設計書 7.3・2.1。
# 見るときは：MSYS_NO_PATHCONV=1 aws logs tail /inquirymanagement/backend --follow（手順書 9.1）

resource "aws_cloudwatch_log_group" "app" {
  for_each = toset(["web", "backend"])

  name              = "/${var.project}/${each.key}"
  retention_in_days = 7 # 常時無料の範囲（月 5 GB）に収める
}
