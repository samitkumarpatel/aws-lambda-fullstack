resource "aws_lambda_function_url" "this" {
  function_name      = var.function_name
  authorization_type = var.authorization_type

  cors {
    allow_credentials = var.cors.allow_credentials
    allow_origins     = var.cors.allow_origins
    allow_methods     = var.cors.allow_methods
    allow_headers     = var.cors.allow_headers
    max_age           = var.cors.max_age
  }
}
