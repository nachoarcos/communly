# ---------------------------------------------------------------------------
# Fan-out: solo necesita leer seguidores (GSI1) y escribir items FEED en la
# tabla base. No necesita SES ni tocar comentarios/reports.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "fan_out_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fan_out" {
  count              = var.shared_execution_role_arn == null ? 1 : 0
  name               = "${local.name_prefix}-fan-out-role"
  assume_role_policy = data.aws_iam_policy_document.fan_out_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "fan_out_permissions" {
  statement {
    sid       = "ReadStream"
    actions   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
    resources = [var.dynamodb_stream_arn]
  }

  statement {
    sid       = "QueryFollowers"
    actions   = ["dynamodb:Query"]
    resources = ["${var.dynamodb_table_arn}/index/GSI1"]
  }

  statement {
    sid       = "WriteFeedItems"
    actions   = ["dynamodb:BatchWriteItem", "dynamodb:PutItem"]
    resources = [var.dynamodb_table_arn]

    condition {
      test     = "ForAllValues:StringLike"
      variable = "dynamodb:LeadingKeys"
      values   = ["USER#*"] # solo puede escribir bajo particiones de usuario (el feed)
    }
  }

  statement {
    sid       = "SendToDlq"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.fan_out_dlq.arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/${local.name_prefix}-fan-out*"]
  }
}

resource "aws_iam_role_policy" "fan_out" {
  count  = var.shared_execution_role_arn == null ? 1 : 0
  name   = "${local.name_prefix}-fan-out-policy"
  role   = aws_iam_role.fan_out[0].id
  policy = data.aws_iam_policy_document.fan_out_permissions.json
}

# ---------------------------------------------------------------------------
# Notificaciones: solo lee el post/autor implicado y envia email.
# No tiene permiso de escritura de contenido en la tabla, solo del propio
# registro de notificacion del destinatario.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "notifications_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "notifications" {
  count              = var.shared_execution_role_arn == null ? 1 : 0
  name               = "${local.name_prefix}-notifications-role"
  assume_role_policy = data.aws_iam_policy_document.notifications_assume.json
  tags               = local.common_tags
}

data "aws_iam_policy_document" "notifications_permissions" {
  statement {
    sid       = "ReadStream"
    actions   = ["dynamodb:DescribeStream", "dynamodb:GetRecords", "dynamodb:GetShardIterator", "dynamodb:ListStreams"]
    resources = [var.dynamodb_stream_arn]
  }

  statement {
    sid       = "ReadPostAndAuthor"
    actions   = ["dynamodb:GetItem"]
    resources = [var.dynamodb_table_arn] # GetItem sobre POST#<id>/META y USER#<sub>/PROFILE
  }

  statement {
    sid       = "WriteNotificationItem"
    actions   = ["dynamodb:PutItem"]
    resources = [var.dynamodb_table_arn]

    condition {
      test     = "ForAllValues:StringLike"
      variable = "dynamodb:LeadingKeys"
      values   = ["USER#*"] # solo puede crear el registro NOTIFICATION del destinatario
    }
  }

  statement {
    sid       = "SendEmail"
    actions   = ["ses:SendEmail", "ses:SendRawEmail"]
    resources = ["*"] # SES no soporta ARNs por identidad en SendEmail; se restringe por FromAddress
    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [var.ses_from_address]
    }
  }

  statement {
    sid       = "SendToDlq"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.notifications_dlq.arn]
  }

  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:log-group:/aws/lambda/${local.name_prefix}-notifications*"]
  }
}

resource "aws_iam_role_policy" "notifications" {
  count  = var.shared_execution_role_arn == null ? 1 : 0
  name   = "${local.name_prefix}-notifications-policy"
  role   = aws_iam_role.notifications[0].id
  policy = data.aws_iam_policy_document.notifications_permissions.json
}
