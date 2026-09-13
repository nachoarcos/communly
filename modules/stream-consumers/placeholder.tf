# Mismo patron que modules/api-lambdas/placeholder.tf: aws_lambda_function
# exige que el objeto en s3_key exista en el momento del apply. Este
# placeholder cubre las dos claves fijas usadas por fan_out.tf y
# notifications.tf hasta que el pipeline suba el codigo real.

terraform {
  required_providers {
    archive = {
      source = "hashicorp/archive"
    }
  }
}

data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/.placeholder.zip"

  source {
    content  = "exports.handler = async () => ({ statusCode: 501, body: 'not deployed yet' });"
    filename = "index.js"
  }
}

resource "aws_s3_object" "fan_out_placeholder" {
  bucket = var.lambda_code_bucket
  key    = var.fan_out_s3_key
  source = data.archive_file.placeholder.output_path
  etag   = data.archive_file.placeholder.output_md5

  lifecycle {
    ignore_changes = [etag, source]
  }
}

resource "aws_s3_object" "notifications_placeholder" {
  bucket = var.lambda_code_bucket
  key    = var.notifications_s3_key
  source = data.archive_file.placeholder.output_path
  etag   = data.archive_file.placeholder.output_md5

  lifecycle {
    ignore_changes = [etag, source]
  }
}
