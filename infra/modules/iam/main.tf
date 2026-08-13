# =============================================================================
# Módulo IAM — Principio de mínimo privilegio
# =============================================================================

resource "aws_iam_user" "dev" {
  name = "${var.project_name}-dev-${var.environment}"
}

resource "aws_iam_access_key" "dev" {
  user = aws_iam_user.dev.name
}

# 1. PERMISOS DE LECTURA TOTAL (Para que Terraform Refresh nunca falle)
resource "aws_iam_user_policy_attachment" "read_only" {
  user       = aws_iam_user.dev.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# 2. PERMISOS DE ESCRITURA — scope estricto por recurso del proyecto
resource "aws_iam_policy" "dev_write_project" {
  name        = "${var.project_name}-dev-write-policy-${var.environment}"
  description = "Permisos de escritura limitados a recursos del proyecto"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ── Storage ──────────────────────────────────────────────────────
      {
        Sid    = "S3ProjectBuckets"
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-*",
          "arn:aws:s3:::${var.project_name}-*/*"
        ]
      },
      {
        Sid      = "DynamoDBProjectTables"
        Effect   = "Allow"
        Action   = ["dynamodb:*"]
        Resource = ["arn:aws:dynamodb:*:*:table/${var.project_name}-*"]
      },
      # ── Compute (ECS/ECR) — scoped ──────────────────────────────────
      {
        Sid    = "ECSProjectResources"
        Effect = "Allow"
        Action = ["ecs:*"]
        Resource = [
          "arn:aws:ecs:*:*:cluster/${var.project_name}-*",
          "arn:aws:ecs:*:*:task-definition/${var.project_name}-*:*",
          "arn:aws:ecs:*:*:service/${var.project_name}-*"
        ]
      },
      {
        Sid      = "ECRProjectRepos"
        Effect   = "Allow"
        Action   = ["ecr:*"]
        Resource = ["arn:aws:ecr:*:*:repository/${var.project_name}-*"]
      },
      {
        Sid      = "ECRGetAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      # ── Messaging — scoped ───────────────────────────────────────────
      {
        Sid      = "SQSProjectQueues"
        Effect   = "Allow"
        Action   = ["sqs:*"]
        Resource = ["arn:aws:sqs:*:*:${var.project_name}-*"]
      },
      # ── API Gateway — scoped ─────────────────────────────────────────
      {
        Sid    = "APIGatewayProjectAPIs"
        Effect = "Allow"
        Action = ["apigateway:*"]
        Resource = [
          "arn:aws:apigateway:*::/apis/*"
        ]
      },
      # ── Secrets Manager — solo /app/* ────────────────────────────────
      {
        Sid      = "SecretsManagerAppSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:*"]
        Resource = ["arn:aws:secretsmanager:*:*:secret:/app/*"]
      },
      # ── Logs — scoped ────────────────────────────────────────────────
      {
        Sid    = "LogsProjectLogGroups"
        Effect = "Allow"
        Action = ["logs:*"]
        Resource = [
          "arn:aws:logs:*:*:log-group:/aws/lambda/${var.project_name}-*",
          "arn:aws:logs:*:*:log-group:/ecs/${var.project_name}-*",
          "arn:aws:logs:*:*:log-group:/aws/apigateway/${var.project_name}-*"
        ]
      },
      # ── Logs Delivery — API Gateway necesita esto para activar access logs ─
      #   logs:CreateLogDelivery / GetLogDelivery operan sobre Resource *
      #   (no sobre un log group), por eso van en statement separado.
      {
        Sid    = "LogsDelivery"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery"
        ]
        Resource = "*"
      },
      # ── IAM — acciones específicas, scope estricto (NO iam:*) ────────
      {
        Sid    = "IAMProjectRoles"
        Effect = "Allow"
        Action = [
          "iam:GetRole", "iam:CreateRole", "iam:DeleteRole",
          "iam:UpdateRole", "iam:TagRole", "iam:UntagRole",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRolePolicy", "iam:ListRolePolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:ListAttachedRolePolicies"
        ]
        Resource = ["arn:aws:iam::*:role/${var.project_name}-*"]
      },
      {
        Sid    = "IAMProjectPolicies"
        Effect = "Allow"
        Action = [
          "iam:GetPolicy", "iam:CreatePolicy", "iam:DeletePolicy",
          "iam:GetPolicyVersion", "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion", "iam:ListPolicyVersions",
          "iam:TagPolicy", "iam:UntagPolicy"
        ]
        Resource = ["arn:aws:iam::*:policy/${var.project_name}-*"]
      },
      {
        Sid      = "IAMPassRoleProjectOnly"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = ["arn:aws:iam::*:role/${var.project_name}-*"]
      },
      {
        Sid      = "IAMListRolesPolicies"
        Effect   = "Allow"
        Action   = ["iam:ListRoles", "iam:ListPolicies"]
        Resource = "*"
      },
      {
        Sid    = "IAMManageOwnAccessKeys"
        Effect = "Allow"
        Action = [
          "iam:CreateAccessKey", "iam:DeleteAccessKey",
          "iam:ListAccessKeys", "iam:UpdateAccessKey"
        ]
        Resource = ["arn:aws:iam::*:user/$${aws:username}"]
      },
      # ── Lambda — scope a funciones del proyecto ──────────────────────
      {
        Sid    = "LambdaProjectFunctions"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction", "lambda:DeleteFunction",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "lambda:GetFunction", "lambda:GetFunctionConfiguration",
          "lambda:TagResource", "lambda:UntagResource", "lambda:ListTags"
        ]
        Resource = ["arn:aws:lambda:*:*:function:${var.project_name}-*"]
      },
      {
        Sid    = "LambdaEventSourceMappings"
        Effect = "Allow"
        Action = [
          "lambda:CreateEventSourceMapping", "lambda:DeleteEventSourceMapping",
          "lambda:GetEventSourceMapping", "lambda:UpdateEventSourceMapping",
          "lambda:ListEventSourceMappings",
          "lambda:TagResource", "lambda:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaPermissions"
        Effect = "Allow"
        Action = [
          "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetPolicy"
        ]
        Resource = ["arn:aws:lambda:*:*:function:${var.project_name}-*"]
      },
      # ── CloudFront — IDs impredecibles, limitado al mínimo necesario ─
      {
        Sid    = "CloudFrontManage"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution", "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution", "cloudfront:GetDistribution",
          "cloudfront:ListDistributions",
          "cloudfront:CreateInvalidation",
          "cloudfront:TagResource", "cloudfront:UntagResource"
        ]
        Resource = "*"
      },
      # ── EC2 — solo security groups para Fargate ─────────────────────
      {
        Sid    = "EC2SecurityGroups"
        Effect = "Allow"
        Action = [
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup",
          "ec2:DescribeSecurityGroups", "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
          "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
          "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
          "ec2:CreateTags", "ec2:DeleteTags"
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
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::${var.project_name}-*/*" },
      { Effect = "Allow", Action = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = "arn:aws:sqs:*:*:${var.project_name}-*" },
      { Effect = "Allow", Action = ["ecs:RunTask"], Resource = "arn:aws:ecs:*:*:task-definition/${var.project_name}-*:*" },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = "arn:aws:iam::*:role/${var.project_name}-fargate-execution-*" },
      { Effect = "Allow", Action = ["ec2:DescribeSecurityGroups", "ec2:DescribeSubnets", "ec2:DescribeVpcs", "ec2:DescribeNetworkInterfaces"], Resource = "*" }
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
      { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = "arn:aws:secretsmanager:*:*:secret:/app/*" }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "fargate_ecs_task_execution" {
  role       = aws_iam_role.fargate_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
