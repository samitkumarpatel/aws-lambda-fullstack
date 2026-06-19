output "cloudfront_domain" {
  value = aws_cloudfront_distribution.datapulse.domain_name
}

output "site_url" {
  value = "https://${var.domain_name}"
}

output "app_url" {
  value = "https://${var.app_subdomain}"
}

output "distribution_id" {
  description = "Use this for manual invalidations: aws cloudfront create-invalidation --distribution-id <id> --paths '/*'"
  value       = aws_cloudfront_distribution.datapulse.id
}

output "nameservers" {
  description = "Set these as NS records at your domain registrar"
  value       = aws_route53_zone.main.name_servers
}

output "waf_arn" {
  value = aws_wafv2_web_acl.datapulse.arn
}
