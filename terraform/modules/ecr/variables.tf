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

variable "source_image" {
  type        = string
  description = "Full image reference to pull and proxy into ECR (e.g. ghcr.io/org/repo:tag)"
  default     = "public.ecr.aws/lambda/java:25"
}

variable "source_image_tag" {
  type        = string
  description = "Tag to use when pushing the proxied image to ECR"
  default     = "latest"
}
