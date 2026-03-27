# =============================================================================
# Módulo IAM - Versión Final de Alta Disponibilidad para CI/CD
# =============================================================================

resource "aws_iam_user" "dev" {
  name = "${var.project_name}-dev-${var.environment}"
}

resource "aws_iam_access_key" "dev" {
  user = aws_iam_user.dev.name
}

# 1. PERMISOS DE LECTURA TOTAL (Para que Terraform Refresh nunca falle)
# Esta política permite ver todo en la cuenta pero NO permite crear ni borrar nada.
resource "aws_iam_user_policy_attachment" "read_only" {
  user       = aws_iam_user.dev.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 2. PERMISOS DE ESCRITURA LIMITADOS AL PROYECTO
# Aquí permitimos que el usuario dev cree, modifique y borre recursos del proyecto.
resource "aws_iam_policy" "dev_write_project" {
  name        = "${var.project_name}-dev-write-policy-${var.environment}"
  description = "Permisos de escritura para recursos del proyecto"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WriteAccessToProjectResources"
        Effect = "Allow"
        Action = [
          "s3:*",
          "dynamodb:*",
          "lambda:*",
          "ecs:*",
          "ecr:*",
          "apigateway:*",
          "cloudfront:*",
          "secretsmanager:*",
          "logs:*"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*",
          "arn:aws:dynamodb:*:*:table/${var.project_name}-*",
          "arn:aws:lambda:*:*:function:${var.project_name}-*",
          "arn:aws:ecs:*:*:cluster/${var.project_name}-*",
          "arn:aws:ecs:*:*:task-definition/${var.project_name}-*:*",
          "arn:aws:ecr:*:*:repository/${var.project_name}-*",
          "arn:aws:logs:*:*:log-group:/aws/lambda/${var.project_name}-*",
          "arn:aws:logs:*:*:log-group:/ecs/${var.project_name}-*",
          "arn:aws:logs:*:*:log-group:/aws/apigateway/${var.project_name}-*",
          "arn:aws:secretsmanager:*:*:secret:/app/*"
        ]
      },
      {
        Sid    = "GlobalWriteActions"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecr:GetAuthorizationToken",
          "iam:PassRole"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "dev_write" {
  user       = aws_iam_user.dev.name
  policy_arn = aws_iam_policy.dev_write_project.arn
}

# =============================================================================
# SECCIÓN 2: Roles de Servicio (Lambda y Fargate)
# =============================================================================

resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-${var.environment}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "lambda_execution" {
  name = "${var.project_name}-lambda-policy-${var.environment}"
  role = aws_iam_role.lambda_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"], Resource = "arn:aws:dynamodb:*:*:table/${var.project_name}-*" },
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::${var.project_name}-*" },
      { Effect = "Allow", Action = ["ecs:RunTask"], Resource = "*" },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = "*" }
    ]
  })
}

resource "aws_iam_role" "fargate_execution" {
  name = "${var.project_name}-fargate-execution-${var.environment}"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ecs-tasks.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "fargate_execution" {
  name = "${var.project_name}-fargate-policy-${var.environment}"
  role = aws_iam_role.fargate_execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "arn:aws:s3:::${var.project_name}-*" },
      { Effect = "Allow", Action = ["dynamodb:UpdateItem"], Resource = "arn:aws:dynamodb:*:*:table/${var.project_name}-*" },
      { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = "arn:aws:secretsmanager:*:*:secret:/app/*" },
      { Effect = "Allow", Action = ["bedrock:InvokeModel"], Resource = "*" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_ecs_task_execution" {
  role       = aws_iam_role.fargate_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
