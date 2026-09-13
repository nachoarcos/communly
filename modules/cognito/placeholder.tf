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
    content  = "def handler(event, context):\n    return event\n"
    filename = "index.py"
  }
}

resource "aws_s3_object" "pre_signup_placeholder" {
  count  = var.manage_lambda_code_with_terraform ? 0 : 1
  bucket = var.lambda_code_bucket
  key    = var.pre_signup_s3_key
  source = data.archive_file.placeholder.output_path
  etag   = data.archive_file.placeholder.output_md5

  lifecycle {
    ignore_changes = [etag, source]
  }
}

resource "aws_s3_object" "post_confirmation_placeholder" {
  count  = var.manage_lambda_code_with_terraform ? 0 : 1
  bucket = var.lambda_code_bucket
  key    = var.post_confirmation_s3_key
  source = data.archive_file.placeholder.output_path
  etag   = data.archive_file.placeholder.output_md5

  lifecycle {
    ignore_changes = [etag, source]
  }
}
