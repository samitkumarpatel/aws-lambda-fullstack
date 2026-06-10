output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "function_url" {
  value = var.enable_function_url ? aws_lambda_function_url.this[0].function_url : null
}

output "url_id" {
  value = var.enable_function_url ? aws_lambda_function_url.this[0].url_id : null
}
