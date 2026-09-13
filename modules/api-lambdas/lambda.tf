resource "aws_lambda_function" "this" {
  for_each = local.functions

  function_name = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  role          = coalesce(var.shared_execution_role_arn, try(aws_iam_role.this[each.key].arn, null))
  runtime       = "python3.12"
  handler       = "index.handler"
  memory_size   = each.value.memory
  timeout       = each.value.timeout

  s3_bucket = var.lambda_code_bucket
  s3_key    = "${var.lambda_code_prefix}/${each.key}.zip"

  environment {
    variables = {
      TABLE_NAME        = var.dynamodb_table_name
      IMAGES_BUCKET     = var.images_bucket_name
      FEED_SHARD_COUNT  = tostring(var.feed_shard_count)
    }
  }

  tags = merge(local.common_tags, {
    AccessPattern = each.key
  })

  # Garantiza que el objeto exista antes de crear la funcion (ver
  # placeholder.tf). Sin este depends_on explicito, Terraform no ve
  # ninguna relacion entre ambos recursos porque s3_key es un string
  # literal, no una referencia.
  depends_on = [aws_s3_object.placeholder]
}

# No se define aqui ningun aws_lambda_permission: el permiso para que
# API Gateway invoque cada funcion se declara en el modulo api-gateway,
# que es quien conoce y posee el recurso invocador.
