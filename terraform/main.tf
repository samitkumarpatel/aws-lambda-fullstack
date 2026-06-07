locals {
  ecr = {
    "aws-lambda-with-spring" = {
      source_image     = "ghcr.io/samitkumarpatel/aws-lambda-with-spring:sha-56df807"
      source_image_tag = "latest"
    }
  }
  s3 = []
  functions = {
    "aws-lambda-with-spring" = {
      api_type                = "http"
      api_gateway_path_prefix = "api"
      memory_size             = 3008
      environment_variables   = {}
    },
    "aws-lambda-with-spring-product" = {
      api_type                = "http"
      api_gateway_path_prefix = "product"
      memory_size             = 3008
      environment_variables = {
        API_BASE_URI = "/product"
      }
    },
    "aws-lambda-with-spring-planning" = {
      api_type                = "http"
      api_gateway_path_prefix = "planning"
      memory_size             = 3008
      environment_variables = {
        API_BASE_URI = "/planning"
      }
    }
  }

  ecr_repos      = local.ecr
  s3_buckets     = toset(local.s3)
  http_functions = { for k, v in local.functions : k => v if v.api_type == "http" }
  url_functions  = { for k, v in local.functions : k => v if v.api_type == "function_url" }
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

  depends_on = [module.ecr]
}

module "function_url" {
  source   = "./modules/function-url"
  for_each = local.url_functions

  function_name = module.lambda[each.key].function_name
}

module "api_gateway" {
  source = "./modules/api-gateway"
  count  = length(local.http_functions) > 0 ? 1 : 0
  name   = "aws-lambda-api"

  integrations = {
    for k, v in local.http_functions :
    "ANY /${v.api_gateway_path_prefix}/{proxy+}" => {
      lambda_function_arn  = module.lambda[k].function_arn
      lambda_function_name = module.lambda[k].function_name
    }
  }
}
