# データベース（RDS for MySQL 8.4）。インフラ設計書 8.。
# 規模は無料利用枠と同じ範囲を上限とする（2.1）。テーブルは Terraform では作らない
# （backend コンテナの起動時に bin/rails db:prepare が作る。8.）。

locals {
  restore_from_snapshot = var.db_snapshot_identifier != ""
}

# RDS を置くサブネット（プライベートサブネット 2 つ）
resource "aws_db_subnet_group" "main" {
  name       = var.project
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_db_instance" "main" {
  identifier = var.project # スクリプトの aws rds コマンドは、この名前（inquirymanagement）を前提にしている

  # --- 作成元（8.1） ---
  # db_snapshot_identifier が指定されていれば、そのスナップショットから復元する。
  snapshot_identifier = local.restore_from_snapshot ? var.db_snapshot_identifier : null

  engine         = "mysql"
  engine_version = "8.4" # ローカル（compose.yaml の mysql:8.4）と同じ系列。マイナー版は RDS の既定に任せる

  # --- 規模（2.1 の上限） ---
  instance_class        = var.db_instance_class
  allocated_storage     = 20
  storage_type          = "gp3"
  storage_encrypted     = true
  multi_az              = false
  max_allocated_storage = null # ストレージの自動拡張はしない

  # --- DB 名とユーザー（ローカルの compose.yaml と同じ名前） ---
  # スナップショットから復元するときは、スナップショットの中の値が使われるため指定しない。
  db_name  = local.restore_from_snapshot ? null : var.project
  username = local.restore_from_snapshot ? null : var.project
  # 復元したときも、復元の直後にこの値へ変更される（再開のたびに新しいパスワードになる。9.）。
  password = random_password.db.result

  # --- ネットワーク ---
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false

  # --- バックアップと削除（8.、8.1） ---
  backup_retention_period  = 1
  delete_automated_backups = true
  copy_tags_to_snapshot    = true
  skip_final_snapshot      = true # 休止前のスナップショットは shutdown.sh が取る
  deletion_protection      = false

  # --- 監視（2.1：有料の監視は使わない） ---
  performance_insights_enabled = false
  monitoring_interval          = 0

  auto_minor_version_upgrade = true
  apply_immediately          = true

  lifecycle {
    # 作成元（スナップショット名など）は作るときにだけ使う。
    # 稼働中に terraform.tfvars の db_snapshot_identifier が変わっても、DB を作り直さない（データが消えるため。12.3）。
    ignore_changes = [snapshot_identifier, db_name, username]
  }
}
