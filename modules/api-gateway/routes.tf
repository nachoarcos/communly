# Una integracion AWS_PROXY + una ruta por access_pattern, generadas a
# partir del output "routes" de api-lambdas. Anadir un access pattern
# nuevo no requiere tocar este fichero, solo el locals.functions de
# api-lambdas.
resource "aws_apigatewayv2_integration" "this" {
  for_each = var.routes

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.function_invoke_arns[each.key]
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "this" {
  for_each = var.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = "${each.value.method} ${each.value.path}"
  target    = "integrations/${aws_apigatewayv2_integration.this[each.key].id}"

  # Solo autentica (token valido de Cognito). La restriccion adicional a
  # "solo administradores" para las rutas admin_only NO se aplica aqui:
  # el JWT Authorizer nativo de una HTTP API no evalua cognito:groups.
  # Cada Lambda con admin_only = true debe leer
  # event.requestContext.authorizer.jwt.claims["cognito:groups"] y
  # devolver 403 si el grupo "admins" no esta presente. Se documenta
  # aqui explicitamente para que la limitacion quede trazada.
  authorization_type = each.value.auth_required ? "JWT" : "NONE"
  authorizer_id       = each.value.auth_required ? aws_apigatewayv2_authorizer.cognito.id : null
}
