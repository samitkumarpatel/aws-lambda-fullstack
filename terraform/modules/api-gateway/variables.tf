variable "name" {
  type = string
}

variable "stage_name" {
  type    = string
  default = "$default"
}

variable "integrations" {
  type = map(object({
    lambda_function_arn  = string
    lambda_function_name = string
    path_rewrites        = optional(map(string), {})
  }))
  description = <<-EOT
    Map of route_key => Lambda target.
    Route key format: "METHOD /path" or "$default" for catch-all.
    Example:
      {
        "GET /ping"       = { lambda_function_arn = "...", lambda_function_name = "..." }
        "POST /orders"    = { lambda_function_arn = "...", lambda_function_name = "..." }
        "$default"        = { lambda_function_arn = "...", lambda_function_name = "..." }
      }
  EOT
}

variable "domain_name" {
  type    = string
  default = null
}

variable "certificate_arn" {
  type    = string
  default = null
}

variable "cors" {
  type = object({
    allow_origins     = list(string)
    allow_methods     = list(string)
    allow_headers     = list(string)
    expose_headers    = list(string)
    max_age           = number
    allow_credentials = bool
  })
  default = {
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    expose_headers    = []
    max_age           = 86400
    allow_credentials = false
  }
}
