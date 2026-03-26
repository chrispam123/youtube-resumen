
output "api_gateway_id" {
  description = "ID del API Gateway v2"
  value       = aws_apigatewayv2_api.main.id
}

output "api_gateway_arn" {
  description = "ARN del API Gateway v2"
  value       = aws_apigatewayv2_api.main.arn
}

output "api_gateway_endpoint" {
  description = "Endpoint del API Gateway (usado por CloudFront como origen)"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "cloudfront_domain_name" {
  description = "Dominio público de CloudFront — esta es la URL de la aplicación"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "cloudfront_distribution_id" {
  description = "ID de la distribución CloudFront (necesario para invalidaciones de caché)"
  value       = aws_cloudfront_distribution.main.id
}

output "cloudfront_distribution_arn" {
  description = "ARN de la distribución CloudFront"
  value       = aws_cloudfront_distribution.main.arn
}
