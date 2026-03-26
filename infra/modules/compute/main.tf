
# =============================================================================
# Módulo Compute
#
# Gestiona todos los recursos de cómputo del proyecto:
#   - ECR: registro de imágenes Docker para Fargate
#   - ECS: cluster y task definition para Fargate
#   - Lambda: funciones de orquestación ligera
#   - Integración Lambda → API Gateway
# =============================================================================

# =============================================================================
# SECCIÓN 1: ECR — registro de imágenes Docker
# =============================================================================

resource "aws_ecr_repository" "processor" {
  name                 = "${var.project_name}-processor-${var.environment}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # Trivy nativo de ECR escanea cada imagen al subir
  }
}

# Lifecycle policy: mantiene solo las últimas 5 imágenes para controlar costes
resource "aws_ecr_lifecycle_policy" "processor" {
  repository = aws_ecr_repository.processor.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Mantener solo las últimas 5 imágenes"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 5
        }
        action = { type = "expire" }
      }
    ]
  })
}

# =============================================================================
# SECCIÓN 2: ECS — cluster y task definition
# =============================================================================

resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster-${var.environment}"

  setting {
    name  = "containerInsights"
    value = "enabled" # métricas avanzadas en CloudWatch
  }
}

resource "aws_cloudwatch_log_group" "fargate" {
  name              = "/ecs/${var.project_name}-processor-${var.environment}"
  retention_in_days = 14
}

resource "aws_ecs_task_definition" "processor" {
  family                   = "${var.project_name}-processor-${var.environment}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.fargate_cpu
  memory                   = var.fargate_memory
  execution_role_arn       = var.fargate_execution_role_arn
  task_role_arn            = var.fargate_execution_role_arn

  container_definitions = jsonencode([
    {
      name  = "processor"
      image = "${aws_ecr_repository.processor.repository_url}:latest"

      # Las variables de entorno NO sensibles van aquí.
      # Los secretos (YouTube API key) los obtiene el código
      # desde Secrets Manager en tiempo de ejecución.
      environment = [
        { name = "ENVIRONMENT", value = var.environment },
        { name = "DYNAMODB_TABLE", value = var.dynamodb_jobs_table_name },
        { name = "RESULTS_BUCKET", value = var.results_bucket_name },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "BEDROCK_MODEL_ID", value = "anthropic.claude-haiku-20240307-v1:0" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.fargate.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "processor"
        }
      }

      # Fargate requiere este campo aunque no expongamos puertos
      portMappings = []

      essential = true
    }
  ])
}

# =============================================================================
# SECCIÓN 3: Lambda — función analyze
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda_analyze" {
  name              = "/aws/lambda/${var.project_name}-analyze-${var.environment}"
  retention_in_days = 14
}

# El código de Lambda se despliega como un ZIP.
# En este punto creamos un ZIP placeholder vacío para que Terraform
# pueda crear la función. El código real se despliega en el Bloque 6
# y se actualiza mediante el pipeline de CD.
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/placeholder.zip"

  source {
    content  = "def handler(event, context): return {'statusCode': 200}"
    filename = "handler.py"
  }
}

resource "aws_lambda_function" "analyze" {
  function_name = "${var.project_name}-analyze-${var.environment}"
  role          = var.lambda_execution_role_arn
  runtime       = "python3.12"
  handler       = "analyze.handler"
  timeout       = 29 # 1 segundo menos que el límite de API Gateway
  memory_size   = 256

  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT         = var.environment
      DYNAMODB_TABLE      = var.dynamodb_jobs_table_name
      RESULTS_BUCKET      = var.results_bucket_name
      ECS_CLUSTER         = aws_ecs_cluster.main.name
      ECS_TASK_DEFINITION = aws_ecs_task_definition.processor.family
      FARGATE_ROLE_ARN    = var.fargate_execution_role_arn
      AWS_ACCOUNT_ID      = var.aws_account_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_analyze]
}

# =============================================================================
# SECCIÓN 4: Lambda — función status
# =============================================================================

resource "aws_cloudwatch_log_group" "lambda_status" {
  name              = "/aws/lambda/${var.project_name}-status-${var.environment}"
  retention_in_days = 14
}

resource "aws_lambda_function" "status" {
  function_name = "${var.project_name}-status-${var.environment}"
  role          = var.lambda_execution_role_arn
  runtime       = "python3.12"
  handler       = "status.handler"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.lambda_placeholder.output_path
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256

  environment {
    variables = {
      ENVIRONMENT    = var.environment
      DYNAMODB_TABLE = var.dynamodb_jobs_table_name
      RESULTS_BUCKET = var.results_bucket_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_status]
}

# =============================================================================
# SECCIÓN 5: Integración Lambda → API Gateway
# =============================================================================

# Integración para la función analyze
resource "aws_apigatewayv2_integration" "analyze" {
  api_id                 = var.api_gateway_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.analyze.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "analyze" {
  api_id    = var.api_gateway_id
  route_key = "POST /api/analyze"
  target    = "integrations/${aws_apigatewayv2_integration.analyze.id}"
}

# Integración para la función status
resource "aws_apigatewayv2_integration" "status" {
  api_id                 = var.api_gateway_id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.status.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "status" {
  api_id    = var.api_gateway_id
  route_key = "GET /api/status/{job_id}"
  target    = "integrations/${aws_apigatewayv2_integration.status.id}"
}

# Permiso para que API Gateway pueda invocar Lambda analyze
resource "aws_lambda_permission" "analyze" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analyze.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_arn}/*/*"
}

# Permiso para que API Gateway pueda invocar Lambda status
resource "aws_lambda_permission" "status" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.status.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_arn}/*/*"
}
