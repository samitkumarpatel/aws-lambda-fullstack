# ─────────────────────────────────────────────────────────────
# WAF — Web Application Firewall
# Must be scope=CLOUDFRONT and deployed in us-east-1
#
# Rules applied (in priority order):
#  1. Rate limit: 2000 req/5min per IP — stops credential stuffing
#  2. AWSManagedRulesCommonRuleSet — OWASP Top 10 (SQLi, XSS, etc.)
#  3. AWSManagedRulesBotControlRuleSet — scraper / bad bot blocking
#  4. AWSManagedRulesKnownBadInputsRuleSet — Log4Shell, Spring4Shell, etc.
#  5. Geo block — restrict API to allowed countries
# ─────────────────────────────────────────────────────────────
resource "aws_wafv2_web_acl" "datapulse" {
  provider    = aws.us_east_1
  name        = "datapulse-waf"
  description = "WAF for DataPulse CloudFront distribution"
  scope       = "CLOUDFRONT" # required for CF — not REGIONAL

  default_action {
    allow {}  # allow by default, rules below BLOCK specific traffic
  }

  # ── Rule 1: IP-based rate limiting ──────────────────────────
  rule {
    name     = "RateLimitPerIP"
    priority = 1
    action   { block {} }
    statement {
      rate_based_statement {
        limit              = 2000  # requests per 5 minutes per IP
        aggregate_key_type = "IP"
        # Only rate-limit the API — static assets are exempt
        scope_down_statement {
          byte_match_statement {
            field_to_match { uri_path {} }
            positional_constraint = "STARTS_WITH"
            search_string         = "/api/"
            text_transformation { priority = 0; type = "NONE" }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 2: OWASP Top 10 ────────────────────────────────────
  rule {
    name     = "AWSCommonRules"
    priority = 2
    override_action { none {} }  # use the rule group's own actions
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
        # Allow large uploads (dashboard file imports) — body size rule blocks >8KB by default
        rule_action_override {
          name          = "SizeRestrictions_BODY"
          action_to_use { allow {} }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSCommonRules"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 3: Bot control ─────────────────────────────────────
  rule {
    name     = "AWSBotControl"
    priority = 3
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"
        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level = "COMMON" # TARGETED costs extra
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AWSBotControl"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 4: Known bad inputs (CVEs) ─────────────────────────
  rule {
    name     = "KnownBadInputs"
    priority = 4
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # ── Rule 5: Geo block on API ─────────────────────────────────
  # Block API access from regions DataPulse doesn't operate in
  rule {
    name     = "GeoBlockAPI"
    priority = 5
    action   { block {} }
    statement {
      and_statement {
        statement {
          byte_match_statement {
            field_to_match { uri_path {} }
            positional_constraint = "STARTS_WITH"
            search_string         = "/api/"
            text_transformation { priority = 0; type = "NONE" }
          }
        }
        statement {
          not_statement {
            statement {
              geo_match_statement {
                country_codes = ["US", "GB", "DE", "FR", "DK", "SE", "NO", "NL", "AU"]
              }
            }
          }
        }
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "GeoBlockAPI"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "DataPulseWAF"
    sampled_requests_enabled   = true
  }

  tags = { App = "DataPulse" }
}
