output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "api_endpoint" {
  description = "URL de invocacion (dominio *.execute-api.<region>.amazonaws.com), origen a apuntar desde CloudFront"
  value       = aws_apigatewayv2_stage.default.invoke_url
}

output "execution_arn" {
  value = aws_apigatewayv2_api.this.execution_arn
}
