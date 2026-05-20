variable "project_name" {
  description = "Project name — used as a prefix for all resource names"
  type        = string
}

variable "github_org" {
  description = "GitHub username or organization that owns the repo"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "aws_region" {
  description = "AWS region for bootstrap resources"
  type        = string
  default     = "us-east-1"
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub Actions OIDC provider already exists in this account (only one is allowed per account)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to all bootstrap resources"
  type        = map(string)
  default     = {}
}
