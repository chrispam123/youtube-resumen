# =============================================================================
# Entorno de desarrollo
#
# Este fichero orquesta todos los módulos del proyecto para el entorno dev.
# Cada módulo recibe sus variables y expone outputs que otros módulos usan.
# =============================================================================

terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend remoto — usa los recursos creados en el bootstrap
  # Sustituye los valores con los outputs que obtuviste del bootstrap
  backend "s3" {
    bucket       = "yt-summarizer-tfstate-668449743330"
    key          = "dev/terraform.tfstate"
    region       = "eu-west-1"
    use_lockfile = true # reemplaza dynamodb_table, mecanismo nativo de S3
    encrypt      = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application = "youtube-resumen"
      Project     = "youtube-summarizer"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

# Data source para obtener el account ID sin hardcodearlo
data "aws_caller_identity" "current" {}

# =============================================================================
# Módulo IAM
# =============================================================================

module "iam" {
  source = "../../modules/iam"

  project_name     = var.project_name
  environment      = var.environment
  aws_account_id   = data.aws_caller_identity.current.account_id
  aws_region       = var.aws_region
  state_bucket_arn = var.state_bucket_arn
}
# Añade al final de infra/environments/dev/main.tf

module "storage" {
  source = "../../modules/storage"

  project_name           = var.project_name
  environment            = var.environment
  aws_region             = var.aws_region
  aws_account_id         = data.aws_caller_identity.current.account_id
  results_retention_days = 7
  jobs_ttl_hours         = 24
}

module "networking" {
  source = "../../modules/networking"

  project_name        = var.project_name
  environment         = var.environment
  aws_region          = var.aws_region
  aws_account_id      = data.aws_caller_identity.current.account_id
  frontend_bucket_id  = module.storage.frontend_bucket_id
  frontend_bucket_arn = module.storage.frontend_bucket_arn
}

module "compute" {
  source = "../../modules/compute"

  project_name                = var.project_name
  environment                 = var.environment
  aws_region                  = var.aws_region
  aws_account_id              = data.aws_caller_identity.current.account_id
  lambda_execution_role_arn   = module.iam.lambda_execution_role_arn
  fargate_execution_role_arn  = module.iam.fargate_execution_role_arn
  fargate_execution_role_name = module.iam.fargate_execution_role_name
  dynamodb_jobs_table_name    = module.storage.dynamodb_jobs_table_name
  results_bucket_name         = module.storage.results_bucket_name
  api_gateway_id              = module.networking.api_gateway_id
  api_gateway_arn             = module.networking.api_gateway_arn
}
