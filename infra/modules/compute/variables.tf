
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

variable "lambda_execution_role_arn" {
  description = "ARN del rol de ejecución de Lambda (del módulo IAM)"
  type        = string
}

variable "fargate_execution_role_arn" {
  description = "ARN del rol de ejecución de Fargate (del módulo IAM)"
  type        = string
}

variable "fargate_execution_role_name" {
  description = "Nombre del rol de ejecución de Fargate"
  type        = string
}

variable "dynamodb_jobs_table_name" {
  description = "Nombre de la tabla DynamoDB de jobs (del módulo storage)"
  type        = string
}

variable "results_bucket_name" {
  description = "Nombre del bucket S3 de resultados (del módulo storage)"
  type        = string
}

variable "api_gateway_id" {
  description = "ID del API Gateway v2 (del módulo networking)"
  type        = string
}

variable "api_gateway_arn" {
  description = "ARN del API Gateway v2 para permisos de invocación"
  type        = string
}

variable "fargate_cpu" {
  description = "CPU units para la tarea Fargate (256 = 0.25 vCPU)"
  type        = number
  default     = 512
}

variable "fargate_memory" {
  description = "Memoria en MB para la tarea Fargate"
  type        = number
  default     = 1024
}

variable "subnet_ids" {
  description = "Subnets para las tareas Fargate"
  type        = string
}
