terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Requerido por los data "archive_file" de modules/api-lambdas y
    # modules/stream-consumers (placeholder.tf), que generan el .zip
    # dummy usado antes del primer despliegue real de codigo.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
    }
  }
}

# aws_wafv2_web_acl con scope = CLOUDFRONT solo puede crearse en
# us-east-1 (restriccion de CloudFront, no de nuestra region habitual).
# Este alias se pasa explicitamente al modulo "security".
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
    }
  }
}
