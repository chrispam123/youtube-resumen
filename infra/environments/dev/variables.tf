variable "aws_region" {
  description = "Región AWS"
  type        = string
  default     = "eu-west-1"
}

variable "environment" {
  description = "Nombre del entorno"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "yt-summarizer"
}

variable "state_bucket_arn" {
  description = "ARN del bucket S3 del estado de Terraform"
  type        = string
}
