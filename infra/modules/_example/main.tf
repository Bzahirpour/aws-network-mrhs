terraform {
  required_version = "~> 1.14"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Add resources here. Tags are inherited from the provider's default_tags in
# the calling env — only resource-specific tags need to be set here.
