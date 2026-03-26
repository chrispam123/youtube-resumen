
# =============================================================================
# Módulo Storage
#
# Gestiona todo el almacenamiento persistente del proyecto:
#   - S3 bucket para resultados de análisis (con expiración automática)
#   - S3 bucket para el frontend estático
#   - DynamoDB tabla para el estado de los jobs
# =============================================================================

# =============================================================================
# SECCIÓN 1: S3 bucket de resultados
# =============================================================================

resource "aws_s3_bucket" "results" {
  bucket = "${var.project_name}-results-${var.environment}"
}

resource "aws_s3_bucket_versioning" "results" {
  bucket = aws_s3_bucket.results.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "results" {
  bucket = aws_s3_bucket.results.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy: expira los resultados automáticamente.
# Esto controla el coste de S3 sin intervención manual.
resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id

  rule {
    id     = "expire-results"
    status = "Enabled"

    filter {
      prefix = "results/"
    }

    expiration {
      days = var.results_retention_days
    }

    # Limpia también los marcadores de borrado que deja el versionado
    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

# =============================================================================
# SECCIÓN 2: S3 bucket del frontend estático
# =============================================================================

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.project_name}-frontend-${var.environment}"
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# El frontend NO es público directamente.
# CloudFront accede a él mediante una Origin Access Control (OAC),
# que es el mecanismo moderno que reemplaza a las Origin Access Identity (OAI).
# El bucket permanece privado y solo CloudFront puede leerlo.
resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Política del bucket que permite acceso solo desde CloudFront OAC.
# El ARN del OAC lo recibiremos del módulo networking como variable,
# por ahora la política la completamos en el módulo networking para
# evitar dependencia circular entre módulos.

# =============================================================================
# SECCIÓN 3: DynamoDB tabla de jobs
# =============================================================================

resource "aws_dynamodb_table" "jobs" {
  name         = "${var.project_name}-jobs-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }

  # TTL: DynamoDB lee el campo 'ttl' de cada item y borra automáticamente
  # los items cuyo timestamp unix ya haya pasado. Es una limpieza sin coste
  # adicional que evita que la tabla crezca indefinidamente.
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  # Point-in-time recovery: permite restaurar la tabla a cualquier
  # momento de los últimos 35 días. Coste mínimo, valor alto.
  point_in_time_recovery {
    enabled = true
  }
}
