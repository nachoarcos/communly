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

# ---------------------------------------------------------------------------
# Despliegue automatico del frontend (build + sync + invalidate) via
# local-exec. Ver frontend_deploy.tf para la justificacion completa:
# a diferencia de las Lambdas (archive_file, nativo de Terraform), esto
# usa un provisioner local-exec porque "npm run build" no es un recurso
# de ningun proveedor -- es el unico mecanismo que Terraform ofrece para
# ejecutar un paso de compilacion arbitrario, y esta documentado como
# ultimo recurso, no como patron recomendado.
# ---------------------------------------------------------------------------

variable "manage_frontend_with_terraform" {
  description = "Si es true, Terraform ejecuta 'npm install && npm run build' sobre app/frontend, sincroniza dist/ con el bucket y crea una invalidacion de CloudFront, todo en el mismo apply. Requiere node/npm y aws cli disponibles en la maquina donde se ejecuta terraform apply. Pensado para entornos sin CI/CD (dev)."
  type        = bool
  default     = false
}

variable "frontend_vite_api_base_url" {
  description = "VITE_API_BASE_URL para el build del frontend"
  type        = string
  default     = ""
}

variable "frontend_vite_cognito_domain" {
  description = "VITE_COGNITO_DOMAIN para el build del frontend (con https://)"
  type        = string
  default     = ""
}

variable "frontend_vite_cognito_client_id" {
  description = "VITE_COGNITO_CLIENT_ID para el build del frontend"
  type        = string
  default     = ""
}

variable "frontend_vite_redirect_uri" {
  description = "VITE_REDIRECT_URI para el build del frontend"
  type        = string
  default     = "http://localhost:5173/callback"
}

variable "frontend_vite_logout_uri" {
  description = "VITE_LOGOUT_URI para el build del frontend"
  type        = string
  default     = "http://localhost:5173"
}

variable "aws_cli_profile" {
  description = "Perfil de AWS CLI a usar en los comandos 'aws s3 sync'/'aws cloudfront create-invalidation' del local-exec. Vacio = usar las credenciales por defecto del entorno (variable AWS_PROFILE ya exportada, o el perfil default)."
  type        = string
  default     = ""
}

variable "local_exec_shell" {
  description = "SO donde correra 'terraform apply' (determina como se cita el argumento --paths de la invalidacion de CloudFront). 'windows': cmd.exe, sin comillas (Windows no expande '*' antes de pasarlo al programa). 'unix': bash/sh, con comillas simples (sin ellas, la propia shell expandiria '/*' contra el sistema de ficheros real). Por defecto 'windows', el entorno de desarrollo local habitual; cambiar a 'unix' si se ejecuta desde un runner Linux (p.ej. .github/workflows/dev-deploy.yml)."
  type        = string
  default     = "windows"

  validation {
    condition     = contains(["windows", "unix"], var.local_exec_shell)
    error_message = "local_exec_shell debe ser 'windows' o 'unix'."
  }
}
