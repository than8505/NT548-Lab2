output "state_bucket" {
  description = "Đặt giá trị này vào GitHub Variable TF_STATE_BUCKET"
  value       = aws_s3_bucket.tfstate.bucket
}

output "github_actions_role_arn" {
  description = "Đặt giá trị này vào GitHub Variable AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "aws_region" {
  description = "Đặt giá trị này vào GitHub Variable AWS_REGION"
  value       = var.aws_region
}
