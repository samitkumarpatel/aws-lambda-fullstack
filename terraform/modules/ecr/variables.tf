variable "name" {
  type = string
}

variable "image_tag_mutability" {
  type    = string
  default = "MUTABLE"
}

variable "keep_image_count" {
  type    = number
  default = 5
}

variable "aws_region" {
  type = string
}
