variable "project_name" { type = string }
variable "environment"  { type = string }
variable "owner"         { type = string }

variable "dynamodb_table_name"  { type = string }
variable "dynamodb_table_arn"   { type = string }
variable "dynamodb_stream_arn"  { type = string }

variable "lambda_code_bucket" {
  description = "Bucket S3 donde el pipeline de CI/CD sube los .zip de las Lambdas"
  type        = string
}

variable "fan_out_s3_key" {
  description = "Key del artefacto de la Lambda de fan-out dentro de lambda_code_bucket"
  type        = string
}

variable "notifications_s3_key" {
  description = "Key del artefacto de la Lambda de notificaciones"
  type        = string
}

variable "ses_from_address" {
  description = "Direccion verificada en SES usada como remitente"
  type        = string
}

variable "sns_alarm_topic_arn" {
  description = "ARN del topic SNS (modulo observability) al que se notifican las alarmas de DLQ"
  type        = string
}

variable "shared_execution_role_arn" {
  description = "ARN de un rol de ejecucion Lambda YA EXISTENTE, reutilizado por fan-out y notifications en vez de crear un rol propio para cada una. Ver la misma variable en modules/api-lambdas para el contexto completo (entornos con IAM restringido). Null = comportamiento normal."
  type        = string
  default     = null
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
  }
}
