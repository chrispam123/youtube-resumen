
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
