variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "communly"
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment debe ser dev, staging o prod."
  }
}

variable "owner" {
  description = "Responsable del recurso"
  type        = string
}
