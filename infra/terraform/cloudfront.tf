# 入口（CloudFront）。画面と API を同じドメインで配信し、オリジンは EC2 の 1 つだけ。インフラ設計書 6.。
#   *       → EC2 の nginx（画面の静的ファイル。キャッシュする）
#   /api/*  → EC2 の nginx → Rails（キャッシュしない）
# アクセス元は限らない（どこからでも使える。6.4）。
# オリジンへの要求には秘密のヘッダー（X-Origin-Verify）を付け、無い要求は nginx が 403 にする（6.2）。

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
  is_ipv6_enabled     = true # 利用者との間は IPv4 と IPv6 のどちらでも通信できる
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
