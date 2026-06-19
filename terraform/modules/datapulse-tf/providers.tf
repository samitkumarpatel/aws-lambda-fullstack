terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# Primary region — all backend infra lives here
provider "aws" {
  region = var.aws_region
}

# CloudFront + WAF + ACM certificates MUST be in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

variable "aws_region" {
  default = "eu-west-1"
}

variable "domain_name" {
  default = "datapulse.io"
}

variable "app_subdomain" {
  default = "app.datapulse.io"
}
