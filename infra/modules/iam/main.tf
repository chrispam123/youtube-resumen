# =============================================================================
# Módulo IAM
#
# Crea y gestiona todas las identidades del proyecto:
#   - Usuario humano iam-dev para trabajo diario
#   - Rol de ejecución para Lambda
#   - Rol de ejecución para ECS Fargate
#
# Principio aplicado: mínimo privilegio. Cada identidad tiene exactamente
# los permisos que necesita para su función y nada más.
# =============================================================================

# =============================================================================
# SECCIÓN 1: Usuario humano iam-dev
# =============================================================================

resource "aws_iam_user" "dev" {
  name = "${var.project_name}-dev-${var.environment}"

  tags = {
    Purpose = "Usuario de desarrollo para trabajo diario con el proyecto"
  }
}

# Las claves de acceso son las credenciales que irán en ~/.aws/credentials.
# Terraform las crea pero NO las muestra en el plan — solo en el apply.
# Una vez creadas, cópialas inmediatamente al gestor de credenciales.
resource "aws_iam_access_key" "dev" {
  user = aws_iam_user.dev.name
}

# Política para S3: acceso a buckets del proyecto y al estado de Terraform
resource "aws_iam_policy" "dev_s3" {
  name        = "${var.project_name}-dev-s3-${var.environment}"
  description = "Acceso S3 para el usuario de desarrollo"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ProjectBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketPolicy" # Necesario para refresh de Terraform
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
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketPolicy" # Necesario para refresh de Terraform
        ]
        Resource = [var.state_bucket_arn, "${var.state_bucket_arn}/*"]
      }
    ]
  })
}

# Política para compute: Lambda, ECS, ECR
resource "aws_iam_policy" "dev_compute" {
  name        = "${var.project_name}-dev-compute-${var.environment}"
  description = "Acceso a servicios de compute para el usuario de desarrollo"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaProjectFunctions"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction",
          "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction",
          "lambda:CreateFunction",
          "lambda:DeleteFunction",
          "lambda:AddPermission",
          "lambda:GetPolicy"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-*"
      },
      {
        Sid    = "ECSProjectTasks"
        Effect = "Allow"
        Action = [
          "ecs:RunTask",
          "ecs:DescribeTasks",
          "ecs:StopTask",
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:ListTaskDefinitions",
          "ecs:CreateCluster",
          "ecs:DescribeClusters"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRProjectRepositories"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:CreateRepository",
          "ecr:DescribeRepositories",
          "ecr:ListTagsForResource" # Necesario para refresh de Terraform
        ]
        Resource = "*"
      }
    ]
  })
}

# Política para datos y secretos: DynamoDB, Secrets Manager, Bedrock
resource "aws_iam_policy" "dev_data" {
  name        = "${var.project_name}-dev-data-${var.environment}"
  description = "Acceso a datos y secretos para el usuario de desarrollo"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBProjectTables"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeTable",
          "dynamodb:DescribeContinuousBackups" # Necesario para refresh de Terraform
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.project_name}-*"
      },
      {
        Sid    = "SecretsManagerProjectOnly"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:CreateSecret",
          "secretsmanager:UpdateSecret",
          "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/app/*"
      },
      {
        Sid    = "BedrockClaudeHaiku"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-haiku*"
        ]
      }
    ]
  })
}

# Política para red y observabilidad: CloudFront, CloudWatch, IAM PassRole
resource "aws_iam_policy" "dev_network_obs" {
  name        = "${var.project_name}-dev-network-obs-${var.environment}"
  description = "Acceso a red, observabilidad y PassRole para el usuario de desarrollo"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudFrontInvalidations"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:GetDistribution",
          "cloudfront:ListDistributions"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents",
          "logs:FilterLogEvents",
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams"
        ]
        Resource = "*" # DescribeLogGroups requiere "*"
      },
      {
        Sid      = "IAMPassRoleToServices"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = ["lambda.amazonaws.com", "ecs-tasks.amazonaws.com"]
          }
        }
      },
      {
        Sid    = "IAMReadProjectRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:GetUser",
          "iam:GetUserPolicy",
          "iam:ListAttachedUserPolicies",
          "iam:ListUserPolicies",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListAccessKeys",
          "apigateway:GET",
          "cloudfront:GetOriginAccessControl"
        ]
        Resource = "*"
      }
    ]
  })
}

# Adjunta las cuatro políticas al usuario dev
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
# SECCIÓN 2: Rol de ejecución para Lambda
# =============================================================================

resource "aws_iam_role" "lambda_execution" {
  name = "${var.project_name}-lambda-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_execution" {
  name = "${var.project_name}-lambda-policy-${var.environment}"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-*"
      },
      {
        Sid    = "DynamoDBJobs"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.project_name}-jobs-${var.environment}"
      },
      {
        Sid      = "S3ReadResults"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.project_name}-results-${var.environment}/*"
      },
      {
        Sid      = "ECSRunTask"
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = "*"
      },
      {
        Sid      = "PassRoleToFargate"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = aws_iam_role.fargate_execution.arn
      }
    ]
  })
}

# =============================================================================
# SECCIÓN 3: Rol de ejecución para ECS Fargate
# =============================================================================

resource "aws_iam_role" "fargate_execution" {
  name = "${var.project_name}-fargate-execution-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ecs-tasks.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "fargate_execution" {
  name = "${var.project_name}-fargate-policy-${var.environment}"
  role = aws_iam_role.fargate_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/ecs/${var.project_name}-*"
      },
      {
        Sid      = "S3WriteResults"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${var.project_name}-results-${var.environment}/*"
      },
      {
        Sid      = "DynamoDBUpdateJob"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.project_name}-jobs-${var.environment}"
      },
      {
        Sid      = "SecretsManagerProjectOnly"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/app/*"
      },
      {
        Sid    = "BedrockInvokeHaiku"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-haiku*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_ecs_task_execution" {
  role       = aws_iam_role.fargate_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
