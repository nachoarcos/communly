# ---------------------------------------------------------------------------
# pre_signup: valida formato de custom:username y hace una comprobacion
# de unicidad best-effort (GetItem). Solo lectura -- nunca escribe,
# porque en este punto el usuario aun no ha verificado su email y el
# alta puede no llegar a completarse nunca.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "pre_signup" {
  count = var.shared_execution_role_arn == null ? 1 : 0
  name  = "${local.name_prefix}-cognito-pre-signup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "pre_signup_logs" {
  count      = var.shared_execution_role_arn == null ? 1 : 0
  role       = aws_iam_role.pre_signup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "pre_signup_permissions" {
  statement {
    sid       = "ReadUsername"
    actions   = ["dynamodb:GetItem"]
    resources = [var.dynamodb_table_arn]

    condition {
      test     = "ForAllValues:StringLike"
      variable = "dynamodb:LeadingKeys"
      values   = ["USERNAME#*"]
    }
  }
}

resource "aws_iam_role_policy" "pre_signup" {
  count  = var.shared_execution_role_arn == null ? 1 : 0
  name   = "${local.name_prefix}-cognito-pre-signup-policy"
  role   = aws_iam_role.pre_signup[0].id
  policy = data.aws_iam_policy_document.pre_signup_permissions.json
}

resource "aws_lambda_function" "pre_signup" {
  function_name = "${local.name_prefix}-cognito-pre-signup"
  role          = coalesce(var.shared_execution_role_arn, try(aws_iam_role.pre_signup[0].arn, null))
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 5
  memory_size   = 128

  filename         = var.manage_lambda_code_with_terraform ? data.archive_file.pre_signup_source[0].output_path : null
  source_code_hash = var.manage_lambda_code_with_terraform ? data.archive_file.pre_signup_source[0].output_base64sha256 : null
  s3_bucket        = var.manage_lambda_code_with_terraform ? null : var.lambda_code_bucket
  s3_key           = var.manage_lambda_code_with_terraform ? null : var.pre_signup_s3_key

  environment {
    variables = { TABLE_NAME = var.dynamodb_table_name }
  }

  tags       = local.common_tags
  depends_on = [aws_s3_object.pre_signup_placeholder]
}

resource "aws_lambda_permission" "cognito_invoke_pre_signup" {
  statement_id  = "AllowCognitoInvokePreSignup"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.pre_signup.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
}

# ---------------------------------------------------------------------------
# post_confirmation: escribe el perfil definitivo (USER#<sub> +
# USERNAME#<username>, con email denormalizado). Ver nota en el chat:
# si la reserva transaccional del username falla por colision, degrada
# creando el perfil sin username (needs_username = true) en vez de
# intentar deshacer un registro que Cognito ya completo.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "post_confirmation" {
  count = var.shared_execution_role_arn == null ? 1 : 0
  name  = "${local.name_prefix}-cognito-post-confirmation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "post_confirmation_logs" {
  count      = var.shared_execution_role_arn == null ? 1 : 0
  role       = aws_iam_role.post_confirmation[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "post_confirmation_permissions" {
  statement {
    sid       = "WriteUserAndUsernameProfile"
    actions   = ["dynamodb:PutItem"]
    resources = [var.dynamodb_table_arn]

    condition {
      test     = "ForAllValues:StringLike"
      variable = "dynamodb:LeadingKeys"
      values   = ["USER#*", "USERNAME#*"]
    }
  }

  # TransactWriteItems se autoriza como una accion distinta a PutItem,
  # aunque afecte a los mismos items.
  statement {
    sid       = "TransactWriteProfile"
    actions   = ["dynamodb:TransactWriteItems"]
    resources = [var.dynamodb_table_arn]
  }
}

resource "aws_iam_role_policy" "post_confirmation" {
  count  = var.shared_execution_role_arn == null ? 1 : 0
  name   = "${local.name_prefix}-cognito-post-confirmation-policy"
  role   = aws_iam_role.post_confirmation[0].id
  policy = data.aws_iam_policy_document.post_confirmation_permissions.json
}

resource "aws_lambda_function" "post_confirmation" {
  function_name = "${local.name_prefix}-cognito-post-confirmation"
  role          = coalesce(var.shared_execution_role_arn, try(aws_iam_role.post_confirmation[0].arn, null))
  runtime       = "python3.12"
  handler       = "index.handler"
  timeout       = 10
  memory_size   = 128

  filename         = var.manage_lambda_code_with_terraform ? data.archive_file.post_confirmation_source[0].output_path : null
  source_code_hash = var.manage_lambda_code_with_terraform ? data.archive_file.post_confirmation_source[0].output_base64sha256 : null
  s3_bucket        = var.manage_lambda_code_with_terraform ? null : var.lambda_code_bucket
  s3_key           = var.manage_lambda_code_with_terraform ? null : var.post_confirmation_s3_key

  environment {
    variables = { TABLE_NAME = var.dynamodb_table_name }
  }

  tags       = local.common_tags
  depends_on = [aws_s3_object.post_confirmation_placeholder]
}

resource "aws_lambda_permission" "cognito_invoke_post_confirmation" {
  statement_id  = "AllowCognitoInvokePostConfirmation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.post_confirmation.function_name
  principal     = "cognito-idp.amazonaws.com"
  source_arn    = aws_cognito_user_pool.this.arn
}
