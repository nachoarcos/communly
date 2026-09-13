locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
  }
}

# ---------------------------------------------------------------------------
# Frontend: build estatico de la SPA. Solo legible por CloudFront (OAC).
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "frontend" {
  bucket = "${local.name_prefix}-frontend"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration {
    status = "Enabled" # permite rollback de un despliegue de frontend problematico
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

# ---------------------------------------------------------------------------
# Imagenes: subidas por los usuarios via URL prefirmada (Lambda
# request_image_upload). Solo legibles por CloudFront (OAC); la escritura
# la autoriza el IAM de la Lambda, no una policy de bucket.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "images" {
  bucket = "${local.name_prefix}-images"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "images" {
  bucket                  = aws_s3_bucket.images.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "images" {
  bucket = aws_s3_bucket.images.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# El navegador del usuario hace el PUT directo a S3 con la URL prefirmada
# que devuelve request_image_upload: necesita CORS habilitado en el
# bucket, no en API Gateway (esa peticion no pasa por la API).
resource "aws_s3_bucket_cors_configuration" "images" {
  bucket = aws_s3_bucket.images.id

  cors_rule {
    allowed_methods = ["PUT"]
    allowed_origins = var.images_cors_allowed_origins
    allowed_headers = ["*"]
    max_age_seconds = 3000
  }
}

# ---------------------------------------------------------------------------
# Codigo de Lambda: artefactos .zip subidos por el pipeline de CI/CD.
# No se sirve via CloudFront, no es contenido publico.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "lambda_code" {
  bucket = "${local.name_prefix}-lambda-code"
  tags   = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "lambda_code" {
  bucket                  = aws_s3_bucket.lambda_code.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "lambda_code" {
  bucket = aws_s3_bucket.lambda_code.id
  versioning_configuration {
    status = "Enabled" # rollback a un artefacto anterior sin recompilar
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lambda_code" {
  bucket = aws_s3_bucket.lambda_code.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
