output "dev_user_name" {
  description = "Nombre del usuario IAM de desarrollo"
  value       = aws_iam_user.dev.name
}

output "dev_access_key_id" {
  description = "Access Key ID del usuario de desarrollo"
  value       = aws_iam_access_key.dev.id
  # No es un secreto en sí mismo, pero lo marcamos sensitive por precaución
  sensitive = true
}

output "dev_secret_access_key" {
  description = "Secret Access Key del usuario de desarrollo — guárdala inmediatamente"
  value       = aws_iam_access_key.dev.secret
  # sensitive = true significa que Terraform no muestra este valor en los logs
  # Para verlo: terraform output -raw dev_secret_access_key
  sensitive = true
}

output "lambda_execution_role_arn" {
  description = "ARN del rol de ejecución de Lambda"
  value       = aws_iam_role.lambda_execution.arn
}

output "fargate_execution_role_arn" {
  description = "ARN del rol de ejecución de Fargate"
  value       = aws_iam_role.fargate_execution.arn
}

output "fargate_execution_role_name" {
  description = "Nombre del rol de ejecución de Fargate (necesario para ECS task definition)"
  value       = aws_iam_role.fargate_execution.name
}
