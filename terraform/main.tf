locals {

  ecr = {
    "aws-lambda-with-spring" = {
      source_image     = "ghcr.io/samitkumarpatel/aws-lambda-fullstack:latest"
      source_image_tag = "latest"
    }
  }

  s3 = []

  functions = {
    "aws-lambda-with-spring" = {
      memory_size           = 3008
      environment_variables = {}
      enable_function_url   = false
      api_gateway_route_mapping = {
        "ANY /api" = { rewrite = null }
      }
    },
    "aws-lambda-with-spring-product" = {
      memory_size = 3008
      environment_variables = {
        API_BASE_URI = "/product"
      }
      enable_function_url = false
      api_gateway_route_mapping = {
        "ANY /product" = { rewrite = "/product" }
      }
    },
    "aws-lambda-with-spring-planning" = {
      memory_size = 3008
      environment_variables = {
        API_BASE_URI = "/planning"
      }
      enable_function_url = false
      api_gateway_route_mapping = {
        "GET /admin/subscribe"  = { rewrite = "/planning" }
        "GET /nothing" = { rewrite = "/planning" }
      }
    }
  }

  domain = {
    name = "api.your-task.dev"
  }

  ecr_repos  = local.ecr
  s3_buckets = toset(local.s3)

  has_api_gateway_route_mapping = anytrue([for k, v in local.functions : length(try(v.api_gateway_route_mapping, {})) > 0])
}

module "ecr" {
  source           = "./modules/ecr"
  for_each         = local.ecr_repos
  name             = each.key
  aws_region       = "eu-north-1"
  source_image     = each.value.source_image
  source_image_tag = each.value.source_image_tag
}

module "s3" {
  source      = "./modules/s3"
  for_each    = local.s3_buckets
  bucket_name = each.key
}

module "lambda" {
  source   = "./modules/lambda"
  for_each = local.functions

  name                  = each.key
  image_uri             = "${module.ecr["aws-lambda-with-spring"].repository_url}:latest"
  memory_size           = each.value.memory_size
  environment_variables = each.value.environment_variables
  enable_function_url   = each.value.enable_function_url

  depends_on = [module.ecr]
}

# Step 1: create the ACM certificate (DNS validation method)
module "acm" {
  source      = "./modules/acm"
  count       = local.domain.name != "" ? 1 : 0
  domain_name = local.domain.name
}

variable "azure_resource_group" {
  type        = string
  description = "Azure resource group containing the DNS zone"
  default = "DefaultResourceGroup-WEU"
}

variable "azure_dns_zone" {
  type        = string
  description = "Azure DNS zone name (e.g. your-task.dev)"
  default = "your-task.dev"
}

# Step 2: write the validation CNAME records into Azure DNS
resource "azurerm_dns_cname_record" "acm_validation" {
  for_each = local.domain.name != "" ? {
    for dvo in module.acm[0].validation_options : dvo.domain_name => dvo
  } : {}

  name                = trimsuffix(trimsuffix(each.value.resource_record_name, "."), ".${var.azure_dns_zone}")
  zone_name           = var.azure_dns_zone
  resource_group_name = var.azure_resource_group
  ttl                 = 300
  record              = trimsuffix(each.value.resource_record_value, ".")
}

# Step 3: wait for ACM to confirm the certificate is validated. Read more - https://docs.aws.amazon.com/acm/latest/userguide/domain-ownership-validation.html
resource "aws_acm_certificate_validation" "this" {
  count                   = local.domain.name != "" ? 1 : 0
  certificate_arn         = module.acm[0].certificate_arn
  validation_record_fqdns = [for dvo in module.acm[0].validation_options : dvo.resource_record_name]

  depends_on = [azurerm_dns_cname_record.acm_validation]
}

module "api_gateway_route" {
  source = "./modules/api-gateway"
  count  = local.has_api_gateway_route_mapping ? 1 : 0
  name   = "aws-lambda-api"

  domain_name     = local.domain.name != "" ? local.domain.name : null
  certificate_arn = local.domain.name != "" ? aws_acm_certificate_validation.this[0].certificate_arn : null

  integrations = merge([
    for fn_name, fn in local.functions : {
      for route_key, route in try(fn.api_gateway_route_mapping, {}) :
      "${route_key}/{proxy+}" => {
        lambda_function_arn  = module.lambda[fn_name].function_arn
        lambda_function_name = module.lambda[fn_name].function_name
        path_rewrites        = route.rewrite != null ? { "rewrite" = route.rewrite } : {}
      }
    }
  ]...)
}

# Step 5: point api.your-task.dev → API Gateway custom domain in Azure DNS
resource "azurerm_dns_cname_record" "api" {
  count               = local.domain.name != "" ? 1 : 0
  name                = split(".", local.domain.name)[0]
  zone_name           = var.azure_dns_zone
  resource_group_name = var.azure_resource_group
  ttl                 = 300
  record              = module.api_gateway_route[0].custom_domain_target
}
