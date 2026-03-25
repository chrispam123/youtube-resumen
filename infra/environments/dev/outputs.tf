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
