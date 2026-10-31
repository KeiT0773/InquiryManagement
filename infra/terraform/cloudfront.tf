# 入口（CloudFront）。画面と API を同じドメインで配信し、オリジンは EC2 の 1 つだけ。インフラ設計書 6.。
#   *       → EC2 の nginx（画面の静的ファイル。キャッシュする）
#   /api/*  → EC2 の nginx → Rails（キャッシュしない）
# どちらも、自宅の IPv6 のネットワーク以外からの要求は、CloudFront Functions が 403 で拒否する（6.4）。
# オリジンへの要求には秘密のヘッダー（X-Origin-Verify）を付け、無い要求は nginx が 403 にする（6.2）。

# --- アクセス元の制限（CloudFront Functions、6.4） ----------------------------------
# 許可した IPv6 のネットワーク番号以外からの要求に 403 を返す。コードは functions/viewer-allowlist.js。
resource "aws_cloudfront_function" "viewer_allowlist" {
  name    = "${var.project}-viewer-allowlist"
  runtime = "cloudfront-js-2.0"
  comment = "Allow only the home IPv6 network"
  publish = true # 保存と同時に本番（LIVE）に反映する

  # コードの中の目印を、許可リスト（JSON の配列）に置き換える
  code = replace(
    file("${path.module}/functions/viewer-allowlist.js"),
    "%%ALLOWED_PREFIXES%%",
    jsonencode(var.allowed_viewer_ipv6_prefixes)
  )

  lifecycle {
    precondition {
      condition     = length(var.allowed_viewer_ipv6_prefixes) > 0
      error_message = "allowed_viewer_ipv6_prefixes が空です。誰もアクセスできなくなるため中止しました。startup.sh / update-allowed-ip.sh を使うか、terraform.tfvars に自宅の IPv6 のネットワーク番号を書いてください（手順書 6.5）。"
    }
  }
}

# --- AWS が用意しているキャッシュの設定（6.1） ---------------------------------------
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# --- ディストリビューション（CloudFront の本体） -------------------------------------
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  comment             = var.project
  default_root_object = "index.html"
  is_ipv6_enabled     = true # 利用者との間は IPv6 で通信し、アクセス元を判定する（6.4）
  http_version        = "http2and3"
  price_class         = "PriceClass_200" # 日本を含む配信拠点を使う（全拠点の PriceClass_All は不要）

  origin {
    origin_id   = "ec2"
    domain_name = aws_instance.app.public_dns # EC2 を作り直すと変わるが、Terraform が同時に更新する（7.2）

    # 独自ドメインが無く、オリジン用の正規の証明書を得られないため HTTP（6.3）
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    # nginx がこの値を確かめ、一致しなければ 403 を返す（他人の CloudFront からの要求を拒否する。6.2）
    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.origin_verify.result
    }
  }

  # 既定：画面のファイル。キャッシュする
  default_cache_behavior {
    target_origin_id       = "ec2"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_allowlist.arn
    }
  }

  # /api/*：Rails へ転送する。キャッシュせず、ヘッダー・クエリ・本文をすべて渡す
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "ec2"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
    compress                 = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_allowlist.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # *.cloudfront.net の既定の証明書で HTTPS にする（独自ドメインは使わない。2. 方針 10）
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
