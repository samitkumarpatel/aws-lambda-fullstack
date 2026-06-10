locals {

  ecr = {
    "aws-lambda-with-spring" = {
      source_image     = "ghcr.io/samitkumarpatel/aws-lambda-with-spring:latest"
      source_image_tag = "latest"
    }
  }

  s3 = []

  functions = {
    "aws-lambda-with-spring" = {
      memory_size           = 3008
      environment_variables = {}
      enable_function_url   = false #default is false
      api_gateway_route = {
        path_prefix   = "api"
        path_rewrites = {}
      }
    },
    "aws-lambda-with-spring-product" = {
      memory_size = 3008
      environment_variables = {
        API_BASE_URI = "/product"
      }
      enable_function_url = false
      api_gateway_route = {
        path_prefix   = "product"
        path_rewrites = {
          "product" = "/product"
        }
      }
    },
    "aws-lambda-with-spring-planning" = {
      memory_size = 3008
      environment_variables = {
        API_BASE_URI = "/planning"
      }
      enable_function_url = false
      api_gateway_route = {
        path_prefix   = "nothing"
        path_rewrites = {
          "nothing" = "/planning"
        }
      }
    }
  }

  domain = {
    name = "api.your-task.dev"  # e.g. api.example.com
  }

  ecr_repos  = local.ecr
  s3_buckets = toset(local.s3)

  api_gateway_routes = { for k, v in local.functions : k => v if v.api_gateway_route != null }
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

module "acm" {
  source      = "./modules/acm"
  count       = local.domain.name != "" ? 1 : 0
  domain_name = local.domain.name
}

module "api_gateway_route" {
  source = "./modules/api-gateway"
  count  = length(local.api_gateway_routes) > 0 ? 1 : 0
  name   = "aws-lambda-api"

  domain_name     = local.domain.name != "" ? local.domain.name : null
  certificate_arn = local.domain.name != "" ? module.acm[0].certificate_arn : null

  integrations = {
    for k, v in local.api_gateway_routes :
    "ANY /${v.api_gateway_route.path_prefix}/{proxy+}" => {
      lambda_function_arn  = module.lambda[k].function_arn
      lambda_function_name = module.lambda[k].function_name
      path_rewrites        = v.api_gateway_route.path_rewrites
    }
  }
}

# DNS is managed in Azure — add the CNAME records from module.acm[0].validation_records
# into Azure DNS manually, then uncomment this block to create the Route53 alias record
# if DNS is ever migrated to Route53.
#
# module "route53" {
#   source = "./modules/route53"
#   count  = local.domain.name != "" ? 1 : 0
#
#   zone_id       = ""  # Route53 hosted zone ID
#   name          = local.domain.name
#   alias_name    = module.api_gateway_route[0].custom_domain_target
#   alias_zone_id = module.api_gateway_route[0].custom_domain_hosted_zone_id
# }

