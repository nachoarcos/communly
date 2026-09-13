resource "aws_lambda_permission" "apigw" {
  for_each = var.routes

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  action        = "lambda:InvokeFunction"
  function_name = var.function_names[each.key]
  principal     = "apigateway.amazonaws.com"

  # Restringido a esta API concreta, cualquier stage/metodo/ruta de ella.
  source_arn = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
