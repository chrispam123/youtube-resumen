# =============================================================================
# Bootstrap de Terraform
#
# Este fichero se ejecuta UNA SOLA VEZ para crear los recursos que permiten
# a Terraform gestionar su propio estado de forma remota y segura.
#
# NO tiene backend remoto configurado — el estado de este fichero se guarda
# localmente en infra/bootstrap/terraform.tfstate, que está en .gitignore.
# Guarda una copia de seguridad de ese fichero en un lugar seguro.
# =============================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Nota: intencionalmente sin bloque 'backend'.
  # El estado de este bootstrap se guarda local.
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      # Identifica la aplicación en tu cuenta AWS entre todos tus proyectos
      Application = "youtube-resumen"
      # Nombre técnico del proyecto en el repositorio
      Project = "youtube-summarizer" #en el repositorio se llama youtube-resumen igual
      # Indica que este recurso es gestionado por Terraform — no tocar a mano
      ManagedBy = "terraform"
      # Global porque los recursos del bootstrap no pertenecen a dev ni prod
      Environment = "global"
    }
  }
}

# =============================================================================
# Variables
# =============================================================================

variable "aws_region" {
  description = "Región de AWS donde se crean los recursos"
  type        = string
  default     = "eu-west-1"
}

variable "project_name" {
  description = "Nombre del proyecto, usado como prefijo en los recursos"
  type        = string
  default     = "yt-summarizer"
}

# =============================================================================
# S3 Bucket para el estado de Terraform
# =============================================================================

resource "aws_s3_bucket" "terraform_state" {
  # El nombre del bucket debe ser único globalmente en todo AWS.
  # Usamos el account ID para garantizar unicidad sin hardcodear nada.
  bucket = "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"

  # lifecycle prevent_destroy es una guardia de seguridad de Terraform.
  # Impide que 'terraform destroy' elimine este bucket accidentalmente.
  # Si alguna vez necesitas destruirlo, tendrás que quitar este bloque primero.
  lifecycle {
    prevent_destroy = true
  }
}

# Habilita el versionado — guarda historial de cada fichero de estado
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Cifrado en reposo con clave gestionada por AWS (SSE-S3)
# Es gratuito y no requiere gestión de claves KMS
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloquea cualquier acceso público al bucket — el estado nunca debe ser público
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# =============================================================================
# DynamoDB para el bloqueo del estado ya no se usa para el locking YA NO SE DEBERIA CREA UN RECURSO dynamodb_table
# =============================================================================

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "${var.project_name}-tfstate-locks"
  billing_mode = "PAY_PER_REQUEST" # sin capacidad reservada, pago por uso

  # LockID es el nombre de clave que Terraform espera encontrar — no cambiar
  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S" # S = String
  }

  lifecycle {
    prevent_destroy = true
  }
}

# =============================================================================
# Data sources — información sobre la cuenta actual
# =============================================================================

# Obtiene el ID de la cuenta AWS actual sin hardcodearlo
data "aws_caller_identity" "current" {}

# =============================================================================
# Outputs — valores que necesitarás para configurar el backend en otros módulos
# =============================================================================

output "state_bucket_name" {
  description = "Nombre del bucket S3 que almacena el estado de Terraform"
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_bucket_arn" {
  description = "ARN del bucket S3 del estado"
  value       = aws_s3_bucket.terraform_state.arn
}

output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB para el bloqueo del estado"
  value       = aws_dynamodb_table.terraform_locks.name
}

output "aws_region" {
  description = "Región donde se han creado los recursos"
  value       = var.aws_region
}
