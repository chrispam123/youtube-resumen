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

# Política de mínimo privilegio para el usuario de desarrollo.
# Nota sobre el diseño: en lugar de adjuntar políticas AWS predefinidas
# (como AmazonS3FullAccess), creamos políticas personalizadas que restringen
# el acceso solo a los recursos de este proyecto específico.
# Esto significa más código pero una postura de seguridad mucho más sólida.
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
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      },
      {
        Sid      = "S3TerraformState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
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
          "lambda:InvokeFunction", "lambda:UpdateFunctionCode",
          "lambda:UpdateFunctionConfiguration", "lambda:GetFunction",
          "lambda:CreateFunction", "lambda:DeleteFunction",
          "lambda:AddPermission", "lambda:GetPolicy"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${var.aws_account_id}:function:${var.project_name}-*"
      },
      {
        Sid    = "ECSProjectTasks"
        Effect = "Allow"
        Action = [
          "ecs:RunTask", "ecs:DescribeTasks", "ecs:StopTask",
          "ecs:RegisterTaskDefinition", "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition", "ecs:ListTaskDefinitions",
          "ecs:CreateCluster", "ecs:DescribeClusters"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECRProjectRepositories"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken", "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage",
          "ecr:PutImage", "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
          "ecr:CreateRepository", "ecr:DescribeRepositories"
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
          "dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem",
          "dynamodb:DeleteItem", "dynamodb:DescribeTable"
        ]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.project_name}-*"
      },
      {
        Sid    = "SecretsManagerProjectOnly"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue", "secretsmanager:CreateSecret",
          "secretsmanager:UpdateSecret", "secretsmanager:DescribeSecret"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/app/*"
      },
      {
        Sid      = "BedrockClaudeHaiku"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-haiku*"
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
        Sid      = "CloudFrontInvalidations"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetDistribution", "cloudfront:ListDistributions"]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:GetLogEvents", "logs:FilterLogEvents",
          "logs:DescribeLogGroups", "logs:DescribeLogStreams"
        ]
        Resource = [
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/aws/lambda/${var.project_name}-*",
          "arn:aws:logs:${var.aws_region}:${var.aws_account_id}:log-group:/ecs/${var.project_name}-*"
        ]
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

      # IAM: lectura de roles del proyecto para que Terraform pueda
      # verificar el estado actual durante plan y apply.
      # Solo lectura — no permite crear, modificar ni borrar roles.
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
          "iam:GetPolicyVersion"
        ]
        Resource = [
          "arn:aws:iam::${var.aws_account_id}:role/${var.project_name}-*",
          "arn:aws:iam::${var.aws_account_id}:user/${var.project_name}-*",
          "arn:aws:iam::${var.aws_account_id}:policy/${var.project_name}-*"
        ]
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

# La "trust policy" define quién puede asumir este rol.
# En este caso, solo el servicio Lambda de AWS puede hacerlo.
# Sin esta política, nadie puede usar el rol.
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
      # CloudWatch Logs: Lambda necesita crear y escribir sus propios logs
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
      # DynamoDB: escribir el job inicial y leer el estado para el polling
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
      # S3: leer el resultado cuando el usuario consulta el estado DONE
      {
        Sid      = "S3ReadResults"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.project_name}-results-${var.environment}/*"
      },
      # ECS: lanzar la tarea Fargate cuando llega una solicitud de análisis
      {
        Sid      = "ECSRunTask"
        Effect   = "Allow"
        Action   = ["ecs:RunTask"]
        Resource = "*"
      },
      # IAM PassRole: necesario para que Lambda pueda asignar el rol
      # de Fargate cuando lanza la tarea ECS
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
      # CloudWatch Logs: el contenedor escribe sus logs aquí
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
      # S3: escribir el resultado del resumen
      {
        Sid      = "S3WriteResults"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${var.project_name}-results-${var.environment}/*"
      },
      # DynamoDB: actualizar el estado del job (PROCESSING → DONE o ERROR)
      {
        Sid      = "DynamoDBUpdateJob"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = "arn:aws:dynamodb:${var.aws_region}:${var.aws_account_id}:table/${var.project_name}-jobs-${var.environment}"
      },
      # Secrets Manager: obtener la clave de YouTube API
      # La condición de ARN garantiza acceso solo a secretos de este proyecto
      {
        Sid      = "SecretsManagerProjectOnly"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${var.aws_account_id}:secret:/app/*"
      },
      # Bedrock: invocar Claude Haiku para generar el resumen
      {
        Sid      = "BedrockInvokeHaiku"
        Effect   = "Allow"
        Action   = ["bedrock:InvokeModel"]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-haiku*"
      }
      # Nota: Fargate NO tiene permisos para lanzar nuevas tareas ECS.
      # Esto limita el blast radius si el contenedor es comprometido.
    ]
  })
}

# Política gestionada por AWS necesaria para que ECS pueda arrancar el contenedor
# (descargar la imagen de ECR, escribir logs iniciales antes de que el contenedor
# tenga control). Esta es una excepción justificada a "no usar políticas AWS".
resource "aws_iam_role_policy_attachment" "fargate_ecs_task_execution" {
  role       = aws_iam_role.fargate_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
