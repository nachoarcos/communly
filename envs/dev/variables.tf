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
  description = "Region del laboratorio. Confirmado por el error 'InvalidParameter: Invalid parameter: TopicArn' de SNS en un despliegue real: este laboratorio en concreto opera en eu-west-1, con una politica de organizacion que restringe la mayoria de acciones a esa region (WAF/CloudFront es la excepcion esperada, siempre en us-east-1 por requisito de AWS, no de esta variable)."
  type        = string
  default     = "eu-west-1"
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

variable "enable_stream_triggers" {
  description = "Si es false, las Lambdas fan-out/notifications se crean pero NO se conectan al Stream de DynamoDB. Poner a false si el rol compartido no tiene (ni se le puede conceder) dynamodb:GetRecords/GetShardIterator/DescribeStream/ListStreams -- ver modules/stream-consumers/variables.tf."
  type        = bool
  default     = true
}

variable "enable_waf" {
  description = "Si es false, NO se crea el modulo security (WAF Web ACL) y storage recibe waf_web_acl_arn = null. Poner a false si el laboratorio no permite wafv2:* o restringe el uso de us-east-1 de una forma que bloquee este modulo."
  type        = bool
  default     = true
}

variable "mock_ses_notifications" {
  description = "Si es true, la Lambda de notificaciones no intenta enviar el email real via SES -- solo lo registra en el log. Ver modules/stream-consumers/variables.tf. Por defecto activo en dev porque este entorno no suele tener SES concedido."
  type        = bool
  default     = true
}

variable "manage_lambda_code_with_terraform" {
  description = "Si es true, Terraform empaqueta y sube el codigo de las Lambdas directamente (sin S3 ni pipeline externo). Por defecto activo en dev porque no hay CI/CD en este entorno (ver envs/dev/README.md)."
  type        = bool
  default     = true
}
