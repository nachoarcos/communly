variable "project_name" { type = string }
variable "environment"  { type = string }
variable "owner"         { type = string }

variable "callback_urls" {
  description = "URLs a las que Cognito redirige tras login (Hosted UI). Incluye localhost para desarrollo."
  type        = list(string)
}

variable "logout_urls" {
  description = "URLs a las que Cognito redirige tras logout"
  type        = list(string)
}

variable "hosted_ui_domain_prefix" {
  description = "Prefijo del dominio de Cognito, p.ej. 'communly-prod' -> communly-prod.auth.<region>.amazoncognito.com"
  type        = string
}

# Opcional: si se define, Cognito envia los emails (verificacion, reset
# de password) a traves de SES en vez de su cuota interna gratuita
# (limitada y no apta para produccion). Requiere que el dominio/email
# este verificado en SES en la misma cuenta y region.
variable "ses_source_arn" {
  description = "ARN de la identidad SES verificada usada para enviar emails de Cognito. Null = usa la cuota interna de Cognito."
  type        = string
  default     = null
}

variable "ses_from_address" {
  type    = string
  default = null
}

# ---------------------------------------------------------------------------
# Lambda triggers (pre-signup / post-confirmation)
# ---------------------------------------------------------------------------

variable "dynamodb_table_name" {
  description = "Tabla donde los triggers escriben/leen el perfil de usuario"
  type        = string
}

variable "dynamodb_table_arn" {
  type = string
}

variable "lambda_code_bucket" {
  description = "Bucket S3 donde el pipeline sube los .zip de los triggers"
  type        = string
}

variable "pre_signup_s3_key" {
  type    = string
  default = "cognito-triggers/pre-signup.zip"
}

variable "post_confirmation_s3_key" {
  type    = string
  default = "cognito-triggers/post-confirmation.zip"
}

variable "shared_execution_role_arn" {
  description = "ARN de un rol de ejecucion Lambda YA EXISTENTE, reutilizado por los triggers pre-signup y post-confirmation en vez de crear un rol propio para cada uno. Ver la misma variable en modules/api-lambdas para el contexto completo. Null = comportamiento normal."
  type        = string
  default     = null
}
