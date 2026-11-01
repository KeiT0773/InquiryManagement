# 外から渡す入力値。値は terraform.tfvars（Git に含めない）に書く。記入例は terraform.tfvars.example。

variable "region" {
  description = "AWS のリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "project" {
  description = "リソース名の先頭に付ける名前。タグ Project にも使う"
  type        = string
  default     = "inquirymanagement"
}

variable "backend_image_tag" {
  description = "EC2 で動かす backend イメージのタグ（Git のコミットの短縮ハッシュ）。インフラ設計書 7.4"
  type        = string
  default     = ""
  # 空のままでは EC2 を作れない。チェックは ec2.tf の precondition で行う
  # （ECR だけを先に作るとき（-target）には空でよいため、ここでは検証しない）。
}

variable "web_image_tag" {
  description = "EC2 で動かす web イメージ（nginx + 画面）のタグ（Git のコミットの短縮ハッシュ）。インフラ設計書 7.4"
  type        = string
  default     = ""
}

variable "db_snapshot_identifier" {
  description = "DB を復元するスナップショットの名前。空なら DB を新規に作る。インフラ設計書 8.1"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 のインスタンスタイプ"
  type        = string
  default     = "t3.micro"

  # 無料利用枠と同じ規模を上限とする（要件定義書 7.「費用」、インフラ設計書 2.1）。
  # x86_64 にそろえる（PC で作ったイメージをそのまま動かすため。7.1）。
  validation {
    condition     = var.instance_type == "t3.micro"
    error_message = "instance_type は t3.micro にしてください（インフラ設計書 2.1 の上限と 7.1 の CPU の種類）。"
  }
}

variable "db_instance_class" {
  description = "RDS のインスタンスクラス"
  type        = string
  default     = "db.t4g.micro"

  # 無料利用枠と同じ規模を上限とする（要件定義書 7.「費用」、インフラ設計書 2.1）。
  validation {
    condition     = contains(["db.t4g.micro", "db.t3.micro"], var.db_instance_class)
    error_message = "db_instance_class は db.t4g.micro か db.t3.micro にしてください（インフラ設計書 2.1 の上限）。"
  }
}
