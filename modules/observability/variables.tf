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

variable "enable_budget" {
  description = "Si es false, no se crea el aws_budgets_budget. Poner a false si el laboratorio bloquea el servicio Budgets (es un servicio global de facturacion, similar a IAM -- no se ha podido confirmar en todos los entornos si la SCP de restriccion de region lo afecta tambien)."
  type        = bool
  default     = true
}

variable "monthly_budget_limit_usd" {
  description = "Limite de presupuesto mensual en USD. Ver estimacion de coste en el README (~12-31 USD/mes segun trafico) para elegir un valor razonable."
  type        = number
  default     = 40
}
