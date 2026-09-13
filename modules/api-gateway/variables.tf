variable "project_name" { type = string }
variable "environment"  { type = string }
variable "owner"         { type = string }

variable "routes" {
  description = "Mapa access_pattern -> {method, path, auth_required, admin_only, function_key}, output del modulo api-lambdas. 'method' es una lista: la mayoria tiene un solo elemento, pero p.ej. toggle_like/toggle_follow declaran [\"PUT\",\"DELETE\"] para evitar el metodo ANY (que intercepta OPTIONS y rompe el CORS automatico, ver routes.tf)."
  type = map(object({
    method        = list(string)
    path          = string
    auth_required = bool
    admin_only    = bool
    function_key  = string
  }))
}

variable "function_invoke_arns" {
  description = "Mapa access_pattern -> invoke_arn, output del modulo api-lambdas"
  type        = map(string)
}

variable "function_names" {
  description = "Mapa access_pattern -> function_name, output del modulo api-lambdas"
  type        = map(string)
}

variable "cognito_user_pool_id" {
  type = string
}

variable "cognito_user_pool_client_id" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "cors_allowed_origins" {
  description = "Origenes permitidos para el SPA (dominio de CloudFront)"
  type        = list(string)
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "throttling_rate_limit" {
  description = "Requests/segundo sostenidos por defecto para todas las rutas"
  type        = number
  default     = 50
}

variable "throttling_burst_limit" {
  type    = number
  default = 100
}
