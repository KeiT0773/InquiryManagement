# EC2（Docker Compose で web（nginx + 画面）と backend（Rails）を動かす）と、そのインスタンスロール。
# インフラ設計書 7.・10.。EC2 は使い捨て：設定はすべて user_data で行い、中で手作業の設定をしない（2. 方針 4）。

# Amazon Linux 2023 の最新の AMI（AWS が公開している SSM のパラメータから取る。7.1）
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  app_dir      = "/opt/${var.project}"
  ecr_registry = split("/", aws_ecr_repository.app["backend"].repository_url)[0]

  compose_yaml = templatefile("${path.module}/templates/compose.yaml.tftpl", {
    region       = var.region
    project      = var.project
    app_dir      = local.app_dir
    ecr_registry = local.ecr_registry
    db_host      = aws_db_instance.main.address
    db_username  = var.project # rds.tf の username と同じ（スナップショットから復元しても変わらない）
  })

  start_sh = templatefile("${path.module}/templates/start.sh.tftpl", {
    region       = var.region
    project      = var.project
    app_dir      = local.app_dir
    ecr_registry = local.ecr_registry
  })
}

# --- インスタンスロール（10.） --------------------------------------------------
resource "aws_iam_role" "ec2" {
  name = "${var.project}-ec2"

  # このロールを名乗ってよいのは EC2 だけ
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# SSM Session Manager（SSH の代わり）と Run Command（デプロイ）を受けるための AWS 管理ポリシー
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "ec2_app" {
  name = "app"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # ECR へのログイン。AWS の仕様で対象を絞れない（10.）
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid      = "EcrPull"
        Effect   = "Allow"
        Action   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
        Resource = [for r in aws_ecr_repository.app : r.arn]
      },
      {
        # 秘密情報とイメージのタグ（ssm.tf）。AWS 管理の鍵（aws/ssm）のため kms:Decrypt の許可は不要
        Sid      = "ReadParameters"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/*"
      },
      {
        # Docker の awslogs ログドライバーがコンテナのログを書く（logs.tf）
        Sid      = "WriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [for g in aws_cloudwatch_log_group.app : "${g.arn}:*"]
      },
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-ec2"
  role = aws_iam_role.ec2.name
}

data "aws_caller_identity" "current" {}

# --- インスタンス（7.1） ----------------------------------------------------------
resource "aws_instance" "app" {
  ami                         = data.aws_ssm_parameter.al2023_ami.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true # 外へ出るため（NAT Gateway を使わない。5.2）。受信は SG で CloudFront だけ
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  # キーペアは作らない（SSH を使わず SSM Session Manager で入る。5.3）

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  # インスタンスのメタデータは、より安全な v2 の方式でだけ読めるようにする
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    project      = var.project
    app_dir      = local.app_dir
    compose_yaml = local.compose_yaml
    start_sh     = local.start_sh
  })
  # user_data を変えたら作り直す（起動時にしか実行されないため。7.2）
  user_data_replace_on_change = true

  tags = { Name = var.project }

  # 起動したらすぐ start.sh がイメージのタグと秘密情報を読むため、パラメータとログの置き場所を先に作る
  depends_on = [aws_ssm_parameter.image_tag, aws_ssm_parameter.secure, aws_cloudwatch_log_group.app]

  lifecycle {
    # AMI は再開のたびに最新を使う。稼働中に新しい AMI が出ても作り直さない
    ignore_changes = [ami]
  }
}
