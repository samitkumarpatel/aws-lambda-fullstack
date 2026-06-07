locals {
  ecr = ["aws-lambda-with-spring"]
  s3  = []
  functions = {
    "aws-lambda-with-spring" = {
      api_type    = "http"
      memory_size = 3008
      environment_variables = {}
    },
    "aws-lambda-with-spring-product" = {
      api_type    = "http"
      memory_size = 3008
      environment_variables = {
        API_BASE_URI = "/product"
      }
    }
  }

  ecr_repos      = toset(local.ecr)
  s3_buckets     = toset(local.s3)
  http_functions = { for k, v in local.functions : k => v if v.api_type == "http" }
  url_functions  = { for k, v in local.functions : k => v if v.api_type == "function_url" }
}

module "ecr" {
  source     = "./modules/ecr"
  for_each   = local.ecr_repos
  name       = each.key
  aws_region = "eu-north-1"
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
    for k in keys(local.http_functions) :
    (length(local.http_functions) == 1 ? "$default" : "ANY /${k}/{proxy+}") => {
      lambda_function_arn  = module.lambda[k].function_arn
      lambda_function_name = module.lambda[k].function_name
    }
  }
}
