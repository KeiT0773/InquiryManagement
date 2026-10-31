# Terraform 本体と、使うプロバイダー（AWS などを操作するプラグイン）のバージョンを固定する。
# インフラ設計書 12.2。

terraform {
  # 1.10 以上：S3 だけで state をロックする機能（backend.tf の use_lockfile）を使うため。
  required_version = ">= 1.10"

  required_providers {
    # AWS を操作するプロバイダー。メジャー版（6）の中でだけ自動で上がるようにする。
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # 秘密の値（DB パスワードなど）を生成するためのプロバイダー（ssm.tf）。
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  # すべてのリソースに自動で付けるタグ。費用の内訳の絞り込みや、タスク管理アプリのリソースとの区別に使う。
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}
