terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Requerido por los data "archive_file" de modules/api-lambdas,
    # modules/stream-consumers y modules/cognito (placeholder.tf).
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
# us-east-1. Si var.aws_region ya es us-east-1 (lo habitual en un
# laboratorio restringido a una sola region), este alias apunta a la
# misma region que el provider por defecto -- sigue siendo necesario
# declararlo porque modules/security lo exige explicitamente
# (configuration_aliases), pero no supone ningun coste ni duplicidad real.
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
