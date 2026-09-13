resource "aws_iam_role" "this" {
  # Vacio cuando se reutiliza un rol compartido (ver variables.tf):
  # ningun rol propio se crea, ninguno se destruye al cambiar de modo.
  # Se itera sobre las claves (toset), no sobre local.functions
  # directamente: evita el error de unificacion de tipos de HCL en el
  # condicional (local.functions tiene "statements" de distinta forma
  # segun la funcion).
  for_each = var.shared_execution_role_arn == null ? toset(keys(local.functions)) : toset([])

  name = "${local.name_prefix}-${replace(each.key, "_", "-")}-role"

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

# Logging basico via la managed policy de AWS: cubre CreateLogGroup/Stream
# y PutLogEvents. Es la unica accion que SI se comparte entre todas las
# funciones (todas necesitan poder escribir sus propios logs).
resource "aws_iam_role_policy_attachment" "logs" {
  for_each   = var.shared_execution_role_arn == null ? toset(keys(local.functions)) : toset([])
  role       = aws_iam_role.this[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Sin condicional: es un data source que solo renderiza JSON en local
# (no llama a AWS, no tiene coste ni efecto secundario), asi que se
# calcula siempre para las 19 funciones. Necesita el objeto completo
# (each.value.statements), no solo la clave -- por eso NO se puede usar
# el mismo truco de toset(keys(...)) que en los recursos de arriba.
data "aws_iam_policy_document" "this" {
  for_each = local.functions

  dynamic "statement" {
    for_each = each.value.statements
    content {
      sid       = statement.value.sid
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "condition" {
        for_each = statement.value.leading_keys == null ? [] : [statement.value.leading_keys]
        content {
          test     = "ForAllValues:StringLike"
          variable = "dynamodb:LeadingKeys"
          values   = condition.value
        }
      }
    }
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = var.shared_execution_role_arn == null ? toset(keys(local.functions)) : toset([])

  name   = "${local.name_prefix}-${replace(each.key, "_", "-")}-policy"
  role   = aws_iam_role.this[each.key].id
  policy = data.aws_iam_policy_document.this[each.key].json
}
