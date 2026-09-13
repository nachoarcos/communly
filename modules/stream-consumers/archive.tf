# Solo se usa cuando var.manage_lambda_code_with_terraform = true.
# fan-out y notifications son autocontenidas (sin shared/), asi que
# basta con zipear el directorio entero.
data "archive_file" "fan_out_source" {
  count       = var.manage_lambda_code_with_terraform ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/dist-fan-out.zip"
  source_dir  = "${path.module}/../../app/stream-consumers/fan-out"
}

data "archive_file" "notifications_source" {
  count       = var.manage_lambda_code_with_terraform ? 1 : 0
  type        = "zip"
  output_path = "${path.module}/dist-notifications.zip"
  source_dir  = "${path.module}/../../app/stream-consumers/notifications"
}
