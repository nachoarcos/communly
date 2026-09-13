variable "project_name" { type = string }
variable "environment"  { type = string }
variable "owner"         { type = string }

variable "lambda_function_names" {
  description = "Mapa clave -> nombre de funcion Lambda (api-lambdas + stream-consumers combinados), para log groups y alarmas de error"
  type        = map(string)
}

variable "api_gateway_id" {
  description = "ID de la HTTP API (modulo api-gateway), para la alarma de 5xx"
  type        = string
}

variable "dynamodb_table_name" {
  description = "Nombre de la tabla (modulo dynamodb), para la alarma de throttling"
  type        = string
}

variable "alarm_email" {
  description = "Direccion de email que recibe las notificaciones de alarma"
  type        = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}
