variable "project_name" {
  type    = string
  default = "communly"
}

variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

variable "github_org" {
  description = "Organizacion o usuario de GitHub propietario del repositorio"
  type        = string
}

variable "github_repo" {
  description = "Nombre del repositorio (sin el org/, solo el nombre)"
  type        = string
}

variable "manage_github_oidc" {
  description = "Si es false, NO se crea el proveedor OIDC ni el rol de GitHub Actions (iam:CreateRole/CreateOpenIDConnectProvider). Solo se crea el backend de tfstate (S3 + DynamoDB). Pensado para cuentas con IAM restringido a un catalogo fijo de roles (p.ej. un laboratorio de formacion), donde el despliegue se hace localmente con las credenciales de la sesion, no via CI/CD."
  type        = bool
  default     = true
}
