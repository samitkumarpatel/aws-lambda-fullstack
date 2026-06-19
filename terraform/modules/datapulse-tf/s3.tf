# ─────────────────────────────────────────────────────────────
# S3 BUCKETS — three separate buckets, all private
# Marketing site (datapulse.io), React SPA (app.*), Static assets (/assets/*)
# ─────────────────────────────────────────────────────────────

locals {
  buckets = {
    marketing = "datapulse-marketing-site"
    app       = "datapulse-react-spa"
    assets    = "datapulse-static-assets"
  }
}

resource "aws_s3_bucket" "buckets" {
  for_each = local.buckets
  bucket   = each.value
}

# Block ALL public access — OAC handles CloudFront → S3 auth
resource "aws_s3_bucket_public_access_block" "buckets" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.buckets[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning on the SPA bucket so deploys are atomic
resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.buckets["app"].id
  versioning_configuration { status = "Enabled" }
}

# ─────────────────────────────────────────────────────────────
# ORIGIN ACCESS CONTROL
# Modern replacement for OAI. Signs every CF → S3 request with SigV4.
# Without this, CloudFront can't read private buckets.
# ─────────────────────────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "datapulse-oac"
  description                       = "OAC for all DataPulse S3 origins"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ─────────────────────────────────────────────────────────────
# S3 BUCKET POLICIES — allow ONLY this CloudFront distribution
# ─────────────────────────────────────────────────────────────
resource "aws_s3_bucket_policy" "buckets" {
  for_each = local.buckets
  bucket   = aws_s3_bucket.buckets[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontOAC"
      Effect = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.buckets[each.key].arn}/*"
      Condition = {
        StringEquals = {
          # Locks to THIS distribution — even other CF distros can't read it
          "AWS:SourceArn" = aws_cloudfront_distribution.datapulse.arn
        }
      }
    }]
  })
}
