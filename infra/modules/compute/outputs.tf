
output "ecr_repository_url" {
  description = "URL del repositorio ECR para push de imágenes Docker"
  value       = aws_ecr_repository.processor.repository_url
}

output "ecs_cluster_name" {
  description = "Nombre del cluster ECS"
  value       = aws_ecs_cluster.main.name
}

output "ecs_task_definition_arn" {
  description = "ARN de la task definition de Fargate"
  value       = aws_ecs_task_definition.processor.arn
}

output "lambda_analyze_arn" {
  description = "ARN de la función Lambda analyze"
  value       = aws_lambda_function.analyze.arn
}

output "lambda_status_arn" {
  description = "ARN de la función Lambda status"
  value       = aws_lambda_function.status.arn
}
