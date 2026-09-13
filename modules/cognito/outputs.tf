output "user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "user_pool_arn" {
  value = aws_cognito_user_pool.this.arn
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.web.id
}

output "hosted_ui_domain" {
  description = "Dominio completo del Hosted UI"
  value       = "${aws_cognito_user_pool_domain.this.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
}

output "admins_group_name" {
  value = aws_cognito_user_pool_group.admins.name
}

output "pre_signup_function_name" {
  value = aws_lambda_function.pre_signup.function_name
}

output "post_confirmation_function_name" {
  value = aws_lambda_function.post_confirmation.function_name
}
