# Una integracion AWS_PROXY por access_pattern (se reutiliza para todos
# sus metodos), generada a partir del output "routes" de api-lambdas.
resource "aws_apigatewayv2_integration" "this" {
  for_each = var.routes

  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.function_invoke_arns[each.key]
  payload_format_version = "2.0"
}

locals {
  # Aplana {access_pattern: {method: [..], path, ...}} a una entrada por
  # combinacion (access_pattern, metodo): un access pattern puede
  # registrar varios metodos sobre la MISMA funcion/integracion (p.ej.
  # toggle_like -> ["PUT", "DELETE"]). Es deliberado no usar "ANY": ese
  # metodo tambien intercepta las peticiones OPTIONS de preflight,
  # enviandolas al JWT Authorizer (que las rechaza al no llevar token)
  # en vez de dejar que API Gateway las resuelva con el CORS automatico
  # de la API -- exactamente lo que le pasa a cualquier ruta que use
  # ANY en una ruta auth_required.
  route_entries = merge([
    for key, route in var.routes : {
      for method in route.method : "${key}#${method}" => {
        function_key  = key
        method        = method
        path          = route.path
        auth_required = route.auth_required
      }
    }
  ]...)
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.route_entries

  api_id    = aws_apigatewayv2_api.this.id
  route_key = "${each.value.method} ${each.value.path}"
  target    = "integrations/${aws_apigatewayv2_integration.this[each.value.function_key].id}"

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
