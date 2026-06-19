# ─────────────────────────────────────────────────────────────
# ROUTE 53 — hosted zone for datapulse.io
# ─────────────────────────────────────────────────────────────
resource "aws_route53_zone" "main" {
  name = var.domain_name
}

# ─────────────────────────────────────────────────────────────
# ACM CERTIFICATE — MUST be us-east-1 for CloudFront
# Covers apex domain + app subdomain in one cert (SAN)
# ─────────────────────────────────────────────────────────────
resource "aws_acm_certificate" "cert" {
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = [
    "www.${var.domain_name}",
    var.app_subdomain,          # app.datapulse.io
    "*.${var.domain_name}"      # wildcard covers any future subdomains
  ]
  validation_method = "DNS"

  lifecycle {
    # Always create the new cert before destroying the old one
    # Without this you get downtime during cert rotation
    create_before_destroy = true
  }
}

# Auto-create DNS CNAME records for ACM to validate ownership
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60

  # for_each deduplicated by domain name — wildcard + apex share the same validation record
  allow_overwrite = true
}

# Terraform waits here until ACM confirms the cert is ISSUED
# CloudFront will reject a PENDING_VALIDATION cert at apply time
resource "aws_acm_certificate_validation" "cert" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# ─────────────────────────────────────────────────────────────
# ROUTE 53 ALIAS RECORDS — A records pointing to CloudFront
# Must use ALIAS (not CNAME) for apex domain (datapulse.io)
# ─────────────────────────────────────────────────────────────
resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.datapulse.domain_name
    zone_id                = aws_cloudfront_distribution.datapulse.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.datapulse.domain_name
    zone_id                = aws_cloudfront_distribution.datapulse.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.app_subdomain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.datapulse.domain_name
    zone_id                = aws_cloudfront_distribution.datapulse.hosted_zone_id
    evaluate_target_health = false
  }
}
