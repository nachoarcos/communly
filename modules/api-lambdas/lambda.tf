resource "aws_lambda_function" "this" {
  for_each = local.functions

  function_name = "${local.name_prefix}-${replace(each.key, "_", "-")}"
  role          = coalesce(var.shared_execution_role_arn, try(aws_iam_role.this[each.key].arn, null))
  runtime       = "python3.12"
  handler       = "index.handler"
  memory_size   = each.value.memory
  timeout       = each.value.timeout

  # Dos formas mutuamente excluyentes de dar el codigo a Lambda: si
  # manage_lambda_code_with_terraform=true, sube el zip empaquetado por
  # Terraform (filename+hash); si no, referencia el objeto S3 que
  # gestiona app-deploy.yml (flujo normal, ver placeholder.tf).
  filename         = var.manage_lambda_code_with_terraform ? data.archive_file.source[each.key].output_path : null
  source_code_hash = var.manage_lambda_code_with_terraform ? data.archive_file.source[each.key].output_base64sha256 : null
  s3_bucket        = var.manage_lambda_code_with_terraform ? null : var.lambda_code_bucket
  s3_key            = var.manage_lambda_code_with_terraform ? null : "${var.lambda_code_prefix}/${each.key}.zip"

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
