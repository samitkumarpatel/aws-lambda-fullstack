terraform {
  required_version = ">= 1.14"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.43"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket  = "tfpocbucket001"
    key     = "aws-lambda-with-spring/terraform.tfstate"
    region  = "eu-north-1"
    encrypt = true
  }
}

provider "aws" {
  region = "eu-north-1"
}
