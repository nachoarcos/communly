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

variable "enable_event_source_mappings" {
  description = "Si es false, NO se crea la conexion Lambda<->DynamoDB Streams (aws_lambda_event_source_mapping). Las funciones fan-out/notifications se crean igualmente, pero no se disparan automaticamente. Pensado para cuando el rol de ejecucion compartido no tiene permisos dynamodb:GetRecords/GetShardIterator/DescribeStream/ListStreams y no hay forma de concederselos (ver iam.tf)."
  type        = bool
  default     = true
}

variable "mock_ses_notifications" {
  description = "Si es true, la Lambda de notificaciones NO intenta llamar a ses:SendEmail en absoluto -- se limita a registrar en el log que habria enviado el correo. Pensado para entornos donde SES no esta concedido (o no interesa verificar direcciones de prueba). El registro de la notificacion en DynamoDB se guarda igual, con o sin este flag: lo unico que se mockea es el envio de email."
  type        = bool
  default     = false
}

variable "manage_lambda_code_with_terraform" {
  description = "Si es true, Terraform empaqueta el codigo de app/stream-consumers/* directamente (archive_file) y lo sube via filename + source_code_hash, sin pasar por S3 ni por un pipeline externo. Ver la misma variable en modules/api-lambdas para el contexto completo."
  type        = bool
  default     = false
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
  }
}
