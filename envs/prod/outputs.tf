output "dynamodb_table_name" {
  value = module.dynamodb.dynamodb_table_name
}

output "api_lambda_routes" {
  description = "Metadatos de enrutado, listos para que el futuro modulo api-gateway los consuma"
  value       = module.api_lambdas.routes
}

output "stream_consumer_dlqs" {
  value = {
    fan_out       = module.stream_consumers.fan_out_dlq_arn
    notifications = module.stream_consumers.notifications_dlq_arn
  }
}

output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.cognito.user_pool_client_id
}

output "cognito_hosted_ui_domain" {
  value = module.cognito.hosted_ui_domain
}

output "api_gateway_endpoint" {
  description = "URL de invocacion de la API, origen a apuntar desde CloudFront para /api/*"
  value       = module.api_gateway.api_endpoint
}

output "cloudfront_domain_name" {
  description = "Dominio publico *.cloudfront.net. Usar este valor para actualizar var.callback_urls / var.logout_urls / var.cors_allowed_origins en la fase 2 del bootstrap (ver nota en main.tf junto a module.cognito)."
  value       = module.storage.cloudfront_domain_name
}

output "frontend_bucket_name" {
  value = module.storage.frontend_bucket_name
}

output "images_bucket_name" {
  value = module.storage.images_bucket_name
}

output "alarms_topic_arn" {
  value = module.observability.alarms_topic_arn
}
