variable "project_name" {
  type    = string
  default = "communly"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "owner" {
  type = string
}

variable "aws_region" {
  description = "Verificar contra las regiones permitidas en el laboratorio -- muchos entornos de formacion restringen a una unica region."
  type        = string
  default     = "us-east-1"
}

variable "ses_from_address" {
  description = "Direccion verificada en SES usada como remitente de notificaciones"
  type        = string
}

variable "callback_urls" {
  description = "URLs a las que Cognito redirige tras login (Hosted UI)"
  type        = list(string)
  default = [
    "http://localhost:5173/callback",
  ]
}

variable "logout_urls" {
  type    = list(string)
  default = ["http://localhost:5173"]
}

variable "hosted_ui_domain_prefix" {
  type    = string
  default = "communly-dev"
}

variable "alarm_email" {
  type = string
}

variable "cors_allowed_origins" {
  type    = list(string)
  default = ["http://localhost:5173"]
}

# ---------------------------------------------------------------------------
# Especificas del entorno de laboratorio: IAM restringido a un catalogo
# fijo de roles predefinidos. Ver modules/api-lambdas/variables.tf
# (shared_execution_role_arn) para el contexto completo.
# ---------------------------------------------------------------------------

variable "student_lambda_role_arn" {
  description = "ARN del rol de ejecucion Lambda predefinido (p.ej. studentLambdaExecutionRole). Si se deja null, se intenta resolver por nombre via data source (requiere permiso iam:GetRole)."
  type        = string
  default     = null
}

variable "student_lambda_role_name" {
  description = "Nombre del rol predefinido a buscar si student_lambda_role_arn es null"
  type        = string
  default     = "studentLambdaExecutionRole"
}

variable "attach_extra_permissions_to_shared_role" {
  description = "Si es true, intenta anadir una policy inline al rol compartido con los permisos que las Lambdas necesitan (DynamoDB/S3/SES/SQS). Requiere iam:PutRolePolicy sobre ESE rol concreto (distinto de iam:CreateRole, puede estar permitido aunque crear roles nuevos no lo este). Si falla, poner a false y verificar a mano en la consola IAM que el rol ya cubre esos permisos."
  type        = bool
  default     = true
}
