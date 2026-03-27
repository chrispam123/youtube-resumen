# =============================================================================
# Módulo IAM - Versión "Full Refresh"
# =============================================================================

resource "aws_iam_user" "dev" {
  name = "${var.project_name}-dev-${var.environment}"
  tags = {
    Purpose = "Usuario de desarrollo para trabajo diario con el proyecto"
  }
}

resource "aws_iam_access_key" "dev" {
  user = aws_iam_user.dev.name
}

# --- POLÍTICA S3: Lectura y Escritura total en buckets del proyecto ---
resource "aws_iam_policy" "dev_s3" {
  name        = "${var.project_name}-dev-s3-${var.environment}"
  description = "Acceso S3 completo para recursos del proyecto"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ProjectBuckets"
        Effect = "Allow"
        Action = [
          "s3:Get*",
          "s3:List*",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      },
      {
        Sid    = "S3TerraformState"
        Effect = "Allow"
        Action = [
          "s3:Get*",
          "s3:List*",
          "s3:PutObject"
        ]
        Resource = [var.state_bucket_arn, "${var.state_bucket_arn}/*"]
      }
    ]
  })
}

# --- POLÍTICA COMPUTE: Lambda, ECS, ECR con permisos de metadatos ---
resource "aws_iam_policy" "dev_compute" {
  name        = "${var.project_name}-dev-compute-${var.environment}"
  description = "Acceso a servicios de compute y sus metadatos"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaProjectFunctions"
        Effect = "Allow"
        Action = [
          "lambda:Get*",
          "lambda:List*",
          "lambda:InvokeFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:AddPermission"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-*"
      },
      {
        Sid    = "ECSProjectTasks"
        Effect = "Allow"
        Action = [
          "ecs:Describe*",
          "ecs:List*",
          "ecs:RunTask",
          "ecs:StopTask",
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:CreateCluster"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRProjectRepositories"
        Effect = "Allow"
        Action = [
          "ecr:Get*",
          "ecr:List*",
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:CreateRepository"
        ]
        Resource = "*"
      }
    ]
  })
}

# --- POLÍTICA DATA: DynamoDB, Secrets y Bedrock ---
resource "aws_iam_policy" "dev_data" {
  name        = "${var.project_name}-dev-data-${var.environment}"
  description = "Acceso a datos, secretos y modelos"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBProjectTables"
        Effect = "Allow"
        Action = [
          "dynamodb:Describe*",
          "dynamodb:List*",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.project_name}-*"
      },
      {
        Sid    = "SecretsManagerProjectOnly"
        Effect = "Allow"
        Action = [
          "secretsmanager:Get*",
          "secretsmanager:List*",
          "secretsmanager:DescribeSecret",
          "secretsmanager:CreateSecret",
          "secretsmanager:UpdateSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/app/*"
      },
      {
        Sid    = "BedrockClaudeHaiku"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:Get*", "bedrock:List*"]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-haiku*",
          "arn:aws:bedrock:${var.aws_region}::foundation-model/google.gemini-2.5-flash*"
        ]
      }
    ]
  })
}

# --- POLÍTICA NETWORK/OBS: CloudFront, Logs e IAM Introspection ---
resource "aws_iam_policy" "dev_network_obs" {
  name        = "${var.project_name}-dev-network-obs-${var.environment}"
  description = "Acceso a red, logs e inspección de IAM"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudFrontProject"
        Effect = "Allow"
        Action = [
          "cloudfront:Get*",
          "cloudfront:List*",
          "cloudfront:CreateInvalidation"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsProject"
        Effect = "Allow"
        Action = [
          "logs:Describe*",
          "logs:List*",
          "logs:GetLogEvents",
          "logs:FilterLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid      = "APIGatewayProject"
        Effect   = "Allow"
        Action   = ["apigateway:GET", "apigateway:List*"]
        Resource = "*"
      },
      {
        Sid    = "IAMReadAndPassRole"
        Effect = "Allow"
        Action = [
          "iam:Get*",
          "iam:List*",
          "iam:PassRole"
        ]
        Resource = "*"
        # Nota: PassRole sigue siendo seguro porque ECS/Lambda validan el Trust Policy del rol
      }
    ]
  })
}

# Adjuntar políticas al usuario
resource "aws_iam_user_policy_attachment" "dev_s3" {
  user       = aws_iam_user.dev.name
  policy_arn = aws_iam_policy.dev_s3.arn
}
resource "aws_iam_user_policy_attachment" "dev_compute" {
  user       = aws_iam_user.dev.name
  policy_arn = aws_iam_policy.dev_compute.arn
}
resource "aws_iam_user_policy_attachment" "dev_data" {
  user       = aws_iam_user.dev.name
  policy_arn = aws_iam_policy.dev_data.arn
}
resource "aws_iam_user_policy_attachment" "dev_network_obs" {
  user       = aws_iam_user.dev.name
  policy_arn = aws_iam_policy.dev_network_obs.arn
}

# =============================================================================
# SECCIÓN 2: Roles de Servicio (Lambda y Fargate) - Sin cambios necesarios
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
      { Sid = "Logs", Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:*:*:*" },
      { Sid = "Dynamo", Effect = "Allow", Action = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"], Resource = "arn:aws:dynamodb:*:*:table/${var.project_name}-*" },
      { Sid = "S3", Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::${var.project_name}-*" },
      { Sid = "ECS", Effect = "Allow", Action = ["ecs:RunTask"], Resource = "*" },
      { Sid = "PassRole", Effect = "Allow", Action = ["iam:PassRole"], Resource = "*" }
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
      { Sid = "Logs", Effect = "Allow", Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"], Resource = "arn:aws:logs:*:*:*" },
      { Sid = "S3", Effect = "Allow", Action = ["s3:PutObject"], Resource = "arn:aws:s3:::${var.project_name}-*" },
      { Sid = "Dynamo", Effect = "Allow", Action = ["dynamodb:UpdateItem"], Resource = "arn:aws:dynamodb:*:*:table/${var.project_name}-*" },
      { Sid = "Secrets", Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = "arn:aws:secretsmanager:*:*:secret:/app/*" },
      { Sid = "Bedrock", Effect = "Allow", Action = ["bedrock:InvokeModel"], Resource = "*" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_ecs_task_execution" {
  role       = aws_iam_role.fargate_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
