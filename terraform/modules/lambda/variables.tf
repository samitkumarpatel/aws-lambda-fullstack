variable "name" {
  type = string
}

variable "image_uri" {
  type = string
}

variable "memory_size" {
  type    = number
  default = 512
}

variable "timeout" {
  type    = number
  default = 30
}

variable "architectures" {
  type    = list(string)
  default = ["x86_64"]
}

variable "environment_variables" {
  type    = map(string)
  default = {}
}

variable "log_retention_days" {
  type    = number
  default = 5
}
