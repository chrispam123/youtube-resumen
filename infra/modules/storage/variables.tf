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

variable "aws_region" {
  description = "Región AWS"
  type        = string
}

variable "aws_account_id" {
  description = "ID de la cuenta AWS"
  type        = string
}

variable "results_retention_days" {
  description = "Días que se conservan los resultados en S3 antes de expirar"
  type        = number
  default     = 7
}

variable "jobs_ttl_hours" {
  description = "Horas que se conservan los jobs en DynamoDB antes de expirar"
  type        = number
  default     = 24
}
