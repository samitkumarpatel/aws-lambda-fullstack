# ─────────────────────────────────────────────────────────────
# CLOUDFRONT DISTRIBUTION — the entire DataPulse entry point
#
# Path routing (evaluated top to bottom, first match wins):
#
#  /api/*          → API Gateway (CachingDisabled, Lambda@Edge auth)
#  /assets/*       → S3 assets bucket (CachingOptimized, long TTL, compress)
#  /app/*          → S3 SPA bucket (short TTL, CF Function rewrite)
#  /*              → S3 marketing bucket (default, medium TTL)
# ─────────────────────────────────────────────────────────────
resource "aws_cloudfront_distribution" "datapulse" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US + EU + Canada edges only
  web_acl_id          = aws_wafv2_web_acl.datapulse.arn
  aliases             = [var.domain_name, "www.${var.domain_name}", var.app_subdomain]

  # ── Origin 1: Marketing site (datapulse.io) ─────────────────
  origin {
    origin_id                = "s3-marketing"
    domain_name              = aws_s3_bucket.buckets["marketing"].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # ── Origin 2: React SPA (app.datapulse.io) ──────────────────
  origin {
    origin_id                = "s3-app"
    domain_name              = aws_s3_bucket.buckets["app"].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # ── Origin 3: Static assets (JS/CSS/images, long-lived) ─────
  origin {
    origin_id                = "s3-assets"
    domain_name              = aws_s3_bucket.buckets["assets"].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  # ── Origin 4: API Gateway (no caching) ──────────────────────
  origin {
    origin_id   = "apigw"
    domain_name = replace(aws_api_gateway_stage.api.invoke_url, "/^https?://([^/]*).*/", "$1")
    origin_path = "/${aws_api_gateway_stage.api.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # ── BEHAVIOR 1: /api/* → API Gateway ────────────────────────
  # CachingDisabled + Lambda@Edge JWT auth on origin request
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "apigw"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false

    # CachingDisabled — TTL=0, nothing stored at edge for API responses
    cache_policy_id = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    # Forward auth headers + custom headers to API GW (exclude Host — API GW rejects it)
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # AllViewerExceptHostHeader

    # Lambda@Edge: verify JWT and inject tenant ID on every API request
    lambda_function_association {
      event_type   = "origin-request"
      lambda_arn   = "${aws_lambda_function.jwt_auth.arn}:${aws_lambda_function.jwt_auth.version}"
      include_body = false
    }
  }

  # ── BEHAVIOR 2: /assets/* → S3 assets bucket ────────────────
  # Long TTL (1 year) — these files have content-hash filenames (e.g. main.a3f2c1.js)
  # so they never need invalidation; new deploys = new filenames.
  ordered_cache_behavior {
    path_pattern           = "/assets/*"
    target_origin_id       = "s3-assets"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true # gzip + brotli on JS/CSS

    cache_policy_id = aws_cloudfront_cache_policy.assets_long_ttl.id

    # Security headers CF function on viewer response
    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.security_headers.arn
    }
  }

  # ── BEHAVIOR 3: /app/* → React SPA ──────────────────────────
  # Short TTL (5 min) — index.html must update when app deploys
  # CF Function rewrites SPA deep links back to /index.html
  ordered_cache_behavior {
    path_pattern           = "/app/*"
    target_origin_id       = "s3-app"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id = aws_cloudfront_cache_policy.spa_short_ttl.id

    # CF Function: SPA route rewrite + A/B variant injection
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }

    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.security_headers.arn
    }
  }

  # ── DEFAULT BEHAVIOR: /* → Marketing site ───────────────────
  default_cache_behavior {
    target_origin_id       = "s3-marketing"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id = aws_cloudfront_cache_policy.marketing_ttl.id

    function_association {
      event_type   = "viewer-response"
      function_arn = aws_cloudfront_function.security_headers.arn
    }
  }

  # ── GEO RESTRICTION ─────────────────────────────────────────
  # Distribution-level geo restriction (WAF handles per-path logic above)
  restrictions {
    geo_restriction {
      restriction_type = "none" # WAF handles geo logic with more granularity
    }
  }

  # ── TLS CERTIFICATE ─────────────────────────────────────────
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"       # Free; works on all modern clients
    minimum_protocol_version = "TLSv1.2_2021"   # Drops TLS 1.0/1.1 — PCI DSS compliant
  }

  # ── CUSTOM ERROR PAGES ──────────────────────────────────────
  # SPA deep-link 403/404 from S3 → serve index.html with 200
  # (S3 returns 403 for missing keys when bucket is private)
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0 # don't cache error responses
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  depends_on = [aws_acm_certificate_validation.cert]

  tags = { App = "DataPulse" }
}

# ─────────────────────────────────────────────────────────────
# CUSTOM CACHE POLICIES
# AWS managed policies cover most cases but we need custom TTLs
# ─────────────────────────────────────────────────────────────

# Assets: 1-year TTL (content-hashed filenames never change)
resource "aws_cloudfront_cache_policy" "assets_long_ttl" {
  name        = "datapulse-assets-1year"
  default_ttl = 31536000  # 1 year in seconds
  max_ttl     = 31536000
  min_ttl     = 86400     # 1 day minimum

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config  { cookie_behavior  = "none" }
    headers_config  { header_behavior  = "none" }
    query_strings_config { query_string_behavior = "none" }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# SPA: 5-minute TTL so deploys propagate quickly
resource "aws_cloudfront_cache_policy" "spa_short_ttl" {
  name        = "datapulse-spa-5min"
  default_ttl = 300   # 5 minutes
  max_ttl     = 300
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config  { cookie_behavior  = "none" }
    headers_config  { header_behavior  = "none" }
    query_strings_config { query_string_behavior = "none" }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}

# Marketing: 1-hour TTL — content changes occasionally
resource "aws_cloudfront_cache_policy" "marketing_ttl" {
  name        = "datapulse-marketing-1hr"
  default_ttl = 3600  # 1 hour
  max_ttl     = 86400 # up to 24h if origin says so
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config  { cookie_behavior  = "none" }
    headers_config  { header_behavior  = "none" }
    query_strings_config { query_string_behavior = "none" }
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true
  }
}
