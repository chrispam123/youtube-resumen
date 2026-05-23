output "sqs_jobs_queue_url" {
  description = "URL de la cola SQS principal de jobs"
  value       = aws_sqs_queue.jobs.url
}

output "sqs_jobs_queue_arn" {
  description = "ARN de la cola SQS principal de jobs"
  value       = aws_sqs_queue.jobs.arn
}

output "sqs_jobs_queue_name" {
  description = "Nombre de la cola SQS principal de jobs"
  value       = aws_sqs_queue.jobs.name
}

output "sqs_jobs_dlq_url" {
  description = "URL de la Dead Letter Queue de jobs"
  value       = aws_sqs_queue.jobs_dlq.url
}

output "sqs_jobs_dlq_arn" {
  description = "ARN de la Dead Letter Queue de jobs"
  value       = aws_sqs_queue.jobs_dlq.arn
}

output "sqs_jobs_dlq_name" {
  description = "Nombre de la Dead Letter Queue de jobs"
  value       = aws_sqs_queue.jobs_dlq.name
}
