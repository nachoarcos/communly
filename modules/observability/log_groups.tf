# ATENCION: si alguna de estas funciones ya se ha invocado antes de este
# apply, el log group ya existe (creado implicitamente por Lambda) y este
# recurso fallara con "already exists". En el flujo normal del proyecto
# (Terraform crea la funcion antes de que el pipeline de la app la
# invoque) esto no deberia ocurrir; si ocurre, se soluciona con
# `terraform import aws_cloudwatch_log_group.lambda["<key>"] /aws/lambda/<function_name>`.
resource "aws_cloudwatch_log_group" "lambda" {
  for_each = var.lambda_function_names

  name              = "/aws/lambda/${each.value}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}
