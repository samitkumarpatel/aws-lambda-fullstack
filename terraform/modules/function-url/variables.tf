variable "function_name" {
  type = string
}

variable "authorization_type" {
  type    = string
  default = "NONE"
}

variable "cors" {
  type = object({
    allow_credentials = bool
    allow_origins     = list(string)
    allow_methods     = list(string)
    allow_headers     = list(string)
    max_age           = number
  })
  default = {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    max_age           = 86400
  }
}
