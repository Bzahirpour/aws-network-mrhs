terraform {
  required_version = "~> 1.14"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Wire up your modules here, e.g.:
# module "networking" {
#   source       = "../../modules/networking"
#   project_name = var.project_name
#   environment  = var.environment
# }
