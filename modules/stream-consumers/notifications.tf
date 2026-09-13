resource "aws_lambda_function" "notifications" {
  function_name = "${local.name_prefix}-notifications"
  role          = coalesce(var.shared_execution_role_arn, try(aws_iam_role.notifications[0].arn, null))
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 15
  memory_size   = 128

  s3_bucket = var.lambda_code_bucket
  s3_key    = var.notifications_s3_key

  environment {
    variables = {
      TABLE_NAME       = var.dynamodb_table_name
      SES_FROM_ADDRESS = var.ses_from_address
      SES_MOCK_MODE    = tostring(var.mock_ses_notifications)
    }
  }

  tags = local.common_tags

  # Garantiza que el objeto exista antes de crear la funcion (ver
  # placeholder.tf).
  depends_on = [aws_s3_object.notifications_placeholder]
}

resource "aws_lambda_event_source_mapping" "notifications" {
  count = var.enable_event_source_mappings ? 1 : 0

  event_source_arn  = var.dynamodb_stream_arn
  function_name     = aws_lambda_function.notifications.arn
  starting_position = "LATEST"

  batch_size                         = 10
  maximum_batching_window_in_seconds = 5

  maximum_retry_attempts         = 3
  maximum_record_age_in_seconds  = 3600
  bisect_batch_on_function_error = true

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.notifications_dlq.arn
    }
  }

  # Solo comentarios nuevos: SK con prefijo COMMENT#
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT"]
        dynamodb = {
          Keys = { SK = { S = [{ prefix = "COMMENT#" }] } }
        }
      })
    }
  }
}
