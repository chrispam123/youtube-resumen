# =============================================================================
# Módulo Mensajes
#
# Gestiona las colas de mensajería asíncrona del proyecto:
#   - SQS principal: buffer entre Lambda analyze y Fargate
#   - SQS DLQ: almacena mensajes que fallaron tras N reintentos
#
# Flujo:
#   Lambda analyze publica { job_id, video_id } en la cola principal.
#   Un Lambda consumer (o directamente Fargate) recibe el mensaje,
#   procesa el job, y borra el mensaje si todo OK.
#   Si falla, el mensaje reaparece (visibilty timeout).
#   Tras 3 fallos, el mensaje pasa a la DLQ para revisión.
# =============================================================================

# =============================================================================
# SECCIÓN 1: Dead Letter Queue (DLQ)
# =============================================================================

resource "aws_sqs_queue" "jobs_dlq" {
  name                      = "${var.project_name}-jobs-dlq-${var.environment}"
  delay_seconds             = 0
  max_message_size          = 262144  # 256 KB
  message_retention_seconds = 1209600 # 14 días — tiempo para revisar fallos
  receive_wait_time_seconds = 0

  tags = {
    Name        = "${var.project_name}-jobs-dlq-${var.environment}"
    Environment = var.environment
  }
}

# =============================================================================
# SECCIÓN 2: Cola principal de jobs
# =============================================================================

resource "aws_sqs_queue" "jobs" {
  name                      = "${var.project_name}-jobs-${var.environment}"
  delay_seconds             = 0
  max_message_size          = 262144 # 256 KB
  message_retention_seconds = 86400  # 24 horas
  receive_wait_time_seconds = 0

  # visibility_timeout: tiempo que un mensaje queda "oculto" para otros
  # consumidores mientras se procesa. Si el consumidor no borra el mensaje
  # en este tiempo, el mensaje reaparece para otro intento.
  # 300s = 5 minutos, suficiente para que Fargate complete o falle.
  visibility_timeout_seconds = 300

  # Redrive policy: después de 3 intentos fallidos (maxReceiveCount),
  # el mensaje se mueve a la DLQ en lugar de perderse.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.jobs_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name        = "${var.project_name}-jobs-${var.environment}"
    Environment = var.environment
  }
}

# =============================================================================
# SECCIÓN 3: Política de la cola para que Lambda pueda publicar
# =============================================================================

data "aws_iam_policy_document" "sqs_policy" {
  statement {
    sid    = "AllowLambdaPublish"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [
      aws_sqs_queue.jobs.arn,
      aws_sqs_queue.jobs_dlq.arn
    ]
  }
}

resource "aws_sqs_queue_policy" "jobs" {
  queue_url = aws_sqs_queue.jobs.id
  policy    = data.aws_iam_policy_document.sqs_policy.json
}
