output "ecr_repository_urls" {
  value = { for k, v in module.ecr : k => v.repository_url }
}

output "s3_bucket_names" {
  value = { for k, v in module.s3 : k => v.bucket_name }
}

output "lambda_function_names" {
  value = { for k, v in module.lambda : k => v.function_name }
}

output "function_urls" {
  value = { for k, v in module.lambda : k => v.function_url if v.function_url != null }
}

output "api_gateway_endpoint" {
  value = length(module.api_gateway_route) > 0 ? module.api_gateway_route[0].api_endpoint : null
}
