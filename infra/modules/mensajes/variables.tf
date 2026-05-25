variable "project_name" {
  description = "Nombre del proyecto usado como prefijo en los recursos"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue: dev o prod"
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "El entorno debe ser 'dev' o 'prod'."
  }
}
