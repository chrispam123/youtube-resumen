variable "project_name" {
  description = "Nombre del proyecto usado como prefijo en todos los recursos IAM"
  type        = string
}

variable "environment" {
  description = "Entorno de despliegue: dev o prod"
  type        = string

  # Terraform permite validar variables para evitar valores incorrectos.
  # Si pasas un valor que no sea dev o prod, terraform plan falla con un
  # mensaje de error claro antes de tocar ningún recurso en AWS.
  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "El entorno debe ser 'dev' o 'prod'."
  }
}

variable "aws_account_id" {
  description = "ID de la cuenta AWS, usado para construir ARNs de recursos"
  type        = string
}

variable "aws_region" {
  description = "Región AWS donde viven los recursos"
  type        = string
}

variable "state_bucket_arn" {
  description = "ARN del bucket S3 del estado de Terraform (para permisos del usuario dev)"
  type        = string
}
