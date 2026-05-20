terraform {
  backend "s3" {
    bucket       = "mrhs-tfstate-453624448159"
    key          = "envs/prod/primary/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
