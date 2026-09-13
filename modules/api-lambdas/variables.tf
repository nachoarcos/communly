variable "project_name" { type = string }
variable "environment"  { type = string }
variable "owner"         { type = string }

variable "dynamodb_table_name" { type = string }
variable "dynamodb_table_arn"  { type = string }

variable "images_bucket_arn" {
  description = "ARN del bucket S3 de imagenes de posts"
  type        = string
}

variable "images_bucket_name" {
  description = "Nombre del bucket S3 de imagenes de posts (el SDK necesita el nombre, no el ARN, para firmar URLs)"
  type        = string
}

variable "feed_shard_count" {
  description = "Numero de shards del feed global (debe coincidir con el usado al escribir GSI1PK=POSTS#<shard>)"
  type        = number
  default     = 5
}

variable "lambda_code_bucket" {
  description = "Bucket S3 donde el pipeline sube los .zip de cada funcion"
  type        = string
}

variable "lambda_code_prefix" {
  description = "Prefijo dentro de lambda_code_bucket; se espera un objeto <prefix>/<function_key>.zip por funcion"
  type        = string
  default     = "api"
}

variable "shared_execution_role_arn" {
  description = "ARN de un rol de ejecucion Lambda YA EXISTENTE y compartido por todas las funciones de este modulo. Pensado para entornos donde IAM esta restringido a un catalogo fijo de roles (p.ej. un laboratorio de formacion) y no se puede crear iam:CreateRole/CreatePolicy. Si se define, NO se crea ningun rol propio por funcion -- se pierde el aislamiento de permisos por access pattern. Null = comportamiento normal (recomendado; un rol de minimo privilegio por funcion)."
  type        = string
  default     = null
}

variable "manage_lambda_code_with_terraform" {
  description = "Si es true, Terraform empaqueta el codigo de app/lambdas/* directamente (archive_file) y lo sube a cada funcion via filename + source_code_hash, sin pasar por S3 ni por un pipeline externo. Pensado para entornos sin CI/CD (dev, despliegue manual). Si es false (por defecto), se mantiene el flujo normal: s3_bucket/s3_key + placeholder, y el codigo real lo sube app-deploy.yml."
  type        = bool
  default     = false
}
