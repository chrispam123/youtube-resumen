# infra/environments/dev/outputs.tf

# Recoge los outputs del módulo IAM y los re-expone en el entorno.
# La sintaxis module.<nombre_del_modulo>.<nombre_del_output> es como
# el entorno "lee" lo que el módulo devuelve.

output "dev_user_name" {
  description = "Nombre del usuario IAM de desarrollo"
  value       = module.iam.dev_user_name
}

output "dev_access_key_id" {
  description = "Access Key ID del usuario de desarrollo"
  value       = module.iam.dev_access_key_id
  sensitive   = true
}

output "dev_secret_access_key" {
  description = "Secret Access Key — guárdala inmediatamente en ~/.aws/credentials"
  value       = module.iam.dev_secret_access_key
  sensitive   = true
}

output "lambda_execution_role_arn" {
  description = "ARN del rol de ejecución de Lambda"
  value       = module.iam.lambda_execution_role_arn
}

output "fargate_execution_role_arn" {
  description = "ARN del rol de ejecución de Fargate"
  value       = module.iam.fargate_execution_role_arn
}
# Añade al final de infra/environments/dev/outputs.tf

output "cloudfront_domain_name" {
  description = "URL pública de la aplicación"
  value       = module.networking.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID de CloudFront para invalidaciones de caché"
  value       = module.networking.cloudfront_distribution_id
}

output "ecr_repository_url" {
  description = "URL de ECR para push de imágenes Docker"
  value       = module.compute.ecr_repository_url
}

output "api_gateway_endpoint" {
  description = "Endpoint directo de API Gateway"
  value       = module.networking.api_gateway_endpoint
}
