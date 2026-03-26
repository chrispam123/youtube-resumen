# =============================================================================
# Módulo Networking
#
# Gestiona la capa de red y entrada del proyecto:
#   - API Gateway v2 (HTTP API) con rutas para Lambda
#   - CloudFront con dos orígenes: S3 (frontend) y API Gateway (/api/*)
#   - Origin Access Control para acceso privado al bucket S3
#   - Política del bucket S3 que autoriza solo a CloudFront
# =============================================================================

# =============================================================================
# SECCIÓN 1: API Gateway v2
# =============================================================================

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api-${var.environment}"
  protocol_type = "HTTP"
  description   = "API HTTP para el summarizer de YouTube"

  # CORS configurado a nivel de API Gateway como respaldo.
  # CloudFront es el punto de entrada real, pero configuramos CORS aquí
  # también para evitar problemas durante el desarrollo local.
  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }
}

# Stage de despliegue — "$default" es el stage principal en HTTP APIs
resource "aws_apigatewayv2_stage" "main" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true

  # Logging de acceso a CloudWatch para debugging
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    # Formato JSON estándar para logs de API Gateway.
    # Estos campos son los más útiles para debugging:
    # requestId para trazar una petición específica,
    # status para ver códigos de respuesta,
    # integrationError para ver errores de Lambda.
    format = jsonencode({
      requestId        = "$context.requestId"
      sourceIp         = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      httpMethod       = "$context.httpMethod"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      protocol         = "$context.protocol"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}-${var.environment}"
  retention_in_days = 14
}

# Las integraciones y rutas las añadiremos desde el módulo compute
# una vez que tengamos los ARNs de Lambda. Por ahora creamos la API
# y el stage, que es lo que necesita CloudFront como origen.

# =============================================================================
# SECCIÓN 2: CloudFront Origin Access Control
# =============================================================================

# OAC es el mecanismo moderno (reemplaza OAI desde 2022) para que
# CloudFront acceda a S3 de forma privada sin exponer el bucket.
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.project_name}-oac-${var.environment}"
  description                       = "OAC para acceso privado al bucket del frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# =============================================================================
# SECCIÓN 3: Distribución CloudFront
# =============================================================================

resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  comment             = "${var.project_name}-${var.environment}"
  price_class         = "PriceClass_100" # Solo Europa y Norteamérica — más barato

  # Origen 1: S3 para ficheros estáticos del frontend
  origin {
    domain_name              = "${var.frontend_bucket_id}.s3.${var.aws_region}.amazonaws.com"
    origin_id                = "S3-${var.frontend_bucket_id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Origen 2: API Gateway para las rutas /api/*
  origin {
    domain_name = replace(aws_apigatewayv2_api.main.api_endpoint, "https://", "")
    origin_id   = "APIGateway-${var.project_name}-${var.environment}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Comportamiento por defecto: sirve el frontend desde S3
  default_cache_behavior {
    target_origin_id       = "S3-${var.frontend_bucket_id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    # TTL del caché para assets estáticos
    min_ttl     = 0
    default_ttl = 3600  # 1 hora
    max_ttl     = 86400 # 24 horas
  }

  # Comportamiento para /api/*: redirige a API Gateway sin caché
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "APIGateway-${var.project_name}-${var.environment}"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Content-Type"]
      cookies {
        forward = "none"
      }
    }

    # Sin caché para las rutas de API — cada petición llega a Lambda
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # SPA routing: cuando CloudFront recibe un 403 o 404 desde S3
  # (porque la ruta es una ruta de React, no un fichero real),
  # devuelve index.html con código 200 para que React Router la gestione.
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # HTTPS con certificado gestionado por CloudFront (dominio *.cloudfront.net)
  # No necesitamos ACM porque usamos el dominio por defecto de CloudFront.
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# =============================================================================
# SECCIÓN 4: Política del bucket S3 que autoriza solo a CloudFront OAC
# =============================================================================

# Esta política vive aquí y no en el módulo storage para evitar
# dependencia circular: storage no puede referenciar networking
# y networking no puede referenciar storage al mismo tiempo.
# La solución es que networking recibe el bucket como variable
# y escribe la política desde aquí.
resource "aws_s3_bucket_policy" "frontend_oac" {
  bucket = var.frontend_bucket_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAC"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${var.frontend_bucket_arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}
