# Solo se usa cuando var.manage_lambda_code_with_terraform = true.
# Ambos triggers son autocontenidos (sin shared/), basta con zipear el
# directorio entero.
data "archive_file" "pre_signup_source" {
  count       = var.manage_lambda_code_with_terraform ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/dist-pre-signup.zip"
  source_dir  = "${path.module}/../../app/cognito-triggers/pre-signup"
}

data "archive_file" "post_confirmation_source" {
  count       = var.manage_lambda_code_with_terraform ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/dist-post-confirmation.zip"
  source_dir  = "${path.module}/../../app/cognito-triggers/post-confirmation"
}
