terraform {
  backend "s3" {
    # Run `terraform output` in bootstrap/ to get the bucket name.
    bucket       = "REPLACE-ME-tfstate-ACCOUNT_ID"
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
