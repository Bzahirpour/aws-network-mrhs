output "tf_state_bucket" {
  description = "S3 bucket name for Terraform remote state — paste into infra/envs/*/backend.tf"
  value       = aws_s3_bucket.tf_state.id
}

output "github_actions_role_arn" {
  description = "IAM role ARN for GitHub Actions — set as the AWS_ROLE_ARN repository secret"
  value       = aws_iam_role.github_actions.arn
}

output "aws_account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}
