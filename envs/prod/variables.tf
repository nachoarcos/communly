variable "project_name" {
  type    = string
  default = "communly"
}

variable "environment" {
  type    = string
  default = "prod"
}

variable "owner" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

# Temporal: hasta que el modulo "ses" gestione la identidad verificada,
# la direccion de envio se pasa como variable.
variable "ses_from_address" {
  description = "Direccion verificada en SES usada como remitente de notificaciones"
  type        = string
}

# ---------------------------------------------------------------------------
# Cognito / API Gateway
# ---------------------------------------------------------------------------

variable "callback_urls" {
  description = "URLs a las que Cognito redirige tras login (Hosted UI)"
  type        = list(string)
  default = [
    "https://communly.example.com/callback",
    "http://localhost:5173/callback", # desarrollo local del SPA
  ]
}

variable "logout_urls" {
  description = "URLs a las que Cognito redirige tras logout"
  type        = list(string)
  default = [
    "https://communly.example.com",
    "http://localhost:5173",
  ]
}

variable "hosted_ui_domain_prefix" {
  description = "Prefijo del dominio de Cognito Hosted UI (debe ser unico en la region)"
  type        = string
  default     = "communly-prod"
}

variable "alarm_email" {
  description = "Direccion de email que recibe las notificaciones de alarma (modulo observability)"
  type        = string
}

variable "cors_allowed_origins" {
  description = "Origenes permitidos por API Gateway para el SPA (dominio de CloudFront)"
  type        = list(string)
  default = [
    "https://communly.example.com",
    "http://localhost:5173",
  ]
}
