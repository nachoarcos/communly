variable "project_name" { type = string }
variable "environment"  { type = string }
variable "owner"         { type = string }

variable "rate_limit_per_5min" {
  description = "Peticiones por IP en una ventana de 5 minutos antes de bloquear (WAF rate-based rule)"
  type        = number
  default     = 2000
}

# Requiere que el modulo se instancie con:
#   providers = { aws.us_east_1 = aws.us_east_1 }
#
# aws_wafv2_web_acl con scope = CLOUDFRONT solo puede crearse en
# us-east-1, sin importar la region del resto de la infraestructura.
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}
