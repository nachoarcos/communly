variable "project_name" { type = string }
variable "environment"  { type = string }
variable "owner"         { type = string }

variable "api_gateway_endpoint" {
  description = "invoke_url del modulo api-gateway, usado como origen dinamico de CloudFront (/api/*)"
  type        = string
}

variable "images_cors_allowed_origins" {
  description = "Origenes permitidos para subir imagenes directamente a S3 via URL prefirmada"
  type        = list(string)
}

variable "price_class" {
  description = "Cobertura geografica de CloudFront. PriceClass_100 = solo NA+EU, mas barato"
  type        = string
  default     = "PriceClass_100"
}

variable "waf_web_acl_arn" {
  description = "ARN del Web ACL de WAF a asociar a CloudFront. Null = sin WAF (se puede anadir despues sin recrear la distribucion)"
  type        = string
  default     = null
}
