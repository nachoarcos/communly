resource "aws_lambda_function" "fan_out" {
  function_name = "${local.name_prefix}-fan-out"
  role          = coalesce(var.shared_execution_role_arn, try(aws_iam_role.fan_out[0].arn, null))
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 30
  memory_size   = 256

  s3_bucket = var.lambda_code_bucket
  s3_key    = var.fan_out_s3_key

  environment {
    variables = {
      TABLE_NAME      = var.dynamodb_table_name
      FEED_ITEM_TTL_S = 60 * 60 * 24 * 90 # 90 dias, coherente con el TTL de la tabla
    }
  }

  tags = local.common_tags

  # Garantiza que el objeto exista antes de crear la funcion (ver
  # placeholder.tf).
  depends_on = [aws_s3_object.fan_out_placeholder]
}

resource "aws_lambda_event_source_mapping" "fan_out" {
  event_source_arn  = var.dynamodb_stream_arn
  function_name     = aws_lambda_function.fan_out.arn
  starting_position = "LATEST"

  batch_size                         = 10
  maximum_batching_window_in_seconds = 5

  # Reintentos acotados: tras 3 intentos o 1h de antiguedad del registro,
  # lo que ocurra antes, el batch se envia a la DLQ y se descarta del stream
  # (sin esto, un registro problematico bloquea el shard indefinidamente).
  maximum_retry_attempts         = 3
  maximum_record_age_in_seconds  = 3600
  bisect_batch_on_function_error = true # aisla el registro que falla dentro del batch

  destination_config {
    on_failure {
      destination_arn = aws_sqs_queue.fan_out_dlq.arn
    }
  }

  # Solo posts que pasan a "published": alta al crearse ya publicado (INSERT)
  # o al transicionar desde draft (MODIFY con status anterior != published).
  filter_criteria {
    filter {
      pattern = jsonencode({
        eventName = ["INSERT"]
        dynamodb = {
          Keys     = { SK = { S = ["META"] } }
          NewImage = { status = { S = ["published"] } }
        }
      })
    }

    filter {
      pattern = jsonencode({
        eventName = ["MODIFY"]
        dynamodb = {
          Keys     = { SK = { S = ["META"] } }
          NewImage = { status = { S = ["published"] } }
          OldImage = { status = { S = [{ "anything-but" = ["published"] }] } }
        }
      })
    }
  }
}
