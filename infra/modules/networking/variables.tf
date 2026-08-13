
variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "aws_account_id" {
  type = string
}

variable "frontend_bucket_id" {
  description = "ID del bucket S3 del frontend para la política OAC"
  type        = string
}

variable "frontend_bucket_arn" {
  description = "ARN del bucket S3 del frontend para la política OAC"
  type        = string
}

variable "throttling_burst_limit" {
  description = "Máximo de peticiones simultáneas permitidas (ráfaga) en API Gateway"
  type        = number
  default     = 20
}

variable "throttling_rate_limit" {
  description = "Peticiones sostenidas por segundo permitidas en API Gateway"
  type        = number
  default     = 10
}
