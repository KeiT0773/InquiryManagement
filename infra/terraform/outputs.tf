# 実行後に表示・取得する値。スクリプトと手順書は `terraform output -raw <名前>` で読む。

output "app_url" {
  description = "画面の URL（再開するたびに変わる）"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront のディストリビューション ID（キャッシュの無効化に使う）"
  value       = aws_cloudfront_distribution.main.id
}

output "instance_id" {
  description = "EC2 のインスタンス ID（SSM Run Command・Session Manager で使う）"
  value       = aws_instance.app.id
}

output "db_instance_identifier" {
  description = "RDS の識別子（スナップショットの作成に使う）"
  value       = aws_db_instance.main.identifier
}

output "ecr_repository_urls" {
  description = "イメージを登録する ECR のアドレス（backend・web）"
  value       = { for k, r in aws_ecr_repository.app : k => r.repository_url }
}

output "log_group_names" {
  description = "コンテナのログのロググループ名（web・backend）"
  value       = { for k, g in aws_cloudwatch_log_group.app : k => g.name }
}
