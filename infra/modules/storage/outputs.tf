
output "results_bucket_name" {
  description = "Nombre del bucket S3 de resultados"
  value       = aws_s3_bucket.results.bucket
}

output "results_bucket_arn" {
  description = "ARN del bucket S3 de resultados"
  value       = aws_s3_bucket.results.arn
}

output "frontend_bucket_name" {
  description = "Nombre del bucket S3 del frontend"
  value       = aws_s3_bucket.frontend.bucket
}

output "frontend_bucket_arn" {
  description = "ARN del bucket S3 del frontend"
  value       = aws_s3_bucket.frontend.arn
}

#El OAC es como una "firma digital". Cuando un usuario pide tu web, CloudFront firma la petición y S3 solo la deja pasar si reconoce esa firma.
output "frontend_bucket_id" {
  description = "ID del bucket S3 del frontend (necesario para la política OAC)"
  value       = aws_s3_bucket.frontend.id
}

output "dynamodb_jobs_table_name" {
  description = "Nombre de la tabla DynamoDB de jobs"
  value       = aws_dynamodb_table.jobs.name
}

output "dynamodb_jobs_table_arn" {
  description = "ARN de la tabla DynamoDB de jobs"
  value       = aws_dynamodb_table.jobs.arn
}
