# ネットワーク：VPC、サブネット、インターネットゲートウェイ、ルートテーブル、セキュリティグループ。
# インフラ設計書 5.。NAT Gateway と VPC エンドポイントは使わない（費用のため。5.2）。

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16" # タスク管理アプリ（10.0.0.0/16）と重ならない範囲（5.1）
  enable_dns_support   = true           # RDS のエンドポイント名を、VPC の中で IP アドレスに変換するため
  enable_dns_hostnames = true           # EC2 にパブリック DNS 名を付ける（CloudFront のオリジンに使う。6.1）

  tags = { Name = var.project }
}

# --- サブネット -------------------------------------------------------------
# パブリック：EC2 を置く。外へ出る経路（インターネットゲートウェイ）を持つ（5.1・5.2）
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.20.1.0/24"
  availability_zone = "${var.region}a"

  tags = { Name = "${var.project}-public-a" }
}

# プライベート：RDS を置く。RDS のサブネットグループは 2 つ以上の AZ を必要とするため 2 つ作る（DB は 1 台）
locals {
  private_subnets = {
    a = "10.20.11.0/24"
    c = "10.20.12.0/24"
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = "${var.region}${each.key}"

  tags = { Name = "${var.project}-private-${each.key}" }
}

# --- インターネットへの出入口と経路 -------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = var.project }
}

# パブリックサブネット用：インターネット宛て（0.0.0.0/0）は IGW へ
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# プライベートサブネット用：VPC の中だけ（外への経路を追加しない）
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${var.project}-private" }
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# --- セキュリティグループ（5.3） -----------------------------------------------

# CloudFront がオリジンへの送信元として使う IP アドレスの一覧（AWS が管理する）
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# EC2：CloudFront からの 80 番だけを受け付ける。SSH（22）は開けない（SSM Session Manager で入る）
resource "aws_security_group" "ec2" {
  name        = "${var.project}-ec2"
  description = "EC2: HTTP from CloudFront only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "ec2_from_cloudfront" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP from CloudFront"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
}

# 送信は全許可：イメージの取得、OS の更新、SSM・CloudWatch Logs との通信、RDS への接続に使う
resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# RDS：EC2 からの 3306 番だけを受け付ける
resource "aws_security_group" "rds" {
  name        = "${var.project}-rds"
  description = "RDS: MySQL from EC2 only"
  vpc_id      = aws_vpc.main.id
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_ec2" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from EC2"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.ec2.id
}
