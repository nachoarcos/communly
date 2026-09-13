output "tfstate_bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}

output "tfstate_locks_table_name" {
  value = aws_dynamodb_table.tfstate_locks.name
}

output "github_actions_role_arn" {
  description = "ARN a usar en el workflow de GitHub Actions (permissions: id-token: write). Null si manage_github_oidc = false: en ese caso no hay CI/CD via OIDC, ver envs/dev/README.md para el flujo de despliegue local."
  value       = try(aws_iam_role.github_actions[0].arn, null)
}
