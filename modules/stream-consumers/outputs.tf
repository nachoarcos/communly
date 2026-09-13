output "fan_out_function_name" {
  description = "Nombre de la Lambda de fan-out del feed"
  value       = aws_lambda_function.fan_out.function_name
}

output "fan_out_function_arn" {
  description = "ARN de la Lambda de fan-out del feed"
  value       = aws_lambda_function.fan_out.arn
}

output "fan_out_role_arn" {
  description = "ARN del rol IAM efectivo de la Lambda de fan-out (propio o compartido)"
  value       = coalesce(var.shared_execution_role_arn, try(aws_iam_role.fan_out[0].arn, null))
}

output "fan_out_dlq_arn" {
  description = "ARN de la DLQ de fan-out"
  value       = aws_sqs_queue.fan_out_dlq.arn
}

output "notifications_function_name" {
  description = "Nombre de la Lambda de notificaciones"
  value       = aws_lambda_function.notifications.function_name
}

output "notifications_function_arn" {
  description = "ARN de la Lambda de notificaciones"
  value       = aws_lambda_function.notifications.arn
}

output "notifications_role_arn" {
  description = "ARN del rol IAM efectivo de la Lambda de notificaciones (propio o compartido)"
  value       = coalesce(var.shared_execution_role_arn, try(aws_iam_role.notifications[0].arn, null))
}

output "notifications_dlq_arn" {
  description = "ARN de la DLQ de notificaciones"
  value       = aws_sqs_queue.notifications_dlq.arn
}
