# ---------------------------------------------------------------------------
# dynamodb: fuente de verdad de todo el dominio. No depende de ningun
# otro modulo.
# ---------------------------------------------------------------------------
module "dynamodb" {
  source = "../../modules/dynamodb"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner
}

# ---------------------------------------------------------------------------
# stream-consumers: reacciona a cambios en la tabla (fan-out del feed,
# notificaciones por comentario). Depende solo de dynamodb + del bucket
# de codigo + del topic de alarmas. No depende de api-lambdas ni viceversa.
# ---------------------------------------------------------------------------
module "stream_consumers" {
  source = "../../modules/stream-consumers"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner

  dynamodb_table_name = module.dynamodb.dynamodb_table_name
  dynamodb_table_arn  = module.dynamodb.dynamodb_table_arn
  dynamodb_stream_arn = module.dynamodb.dynamodb_stream_arn

  lambda_code_bucket    = module.storage.lambda_code_bucket_name
  fan_out_s3_key        = "stream-consumers/fan-out.zip"
  notifications_s3_key  = "stream-consumers/notifications.zip"

  ses_from_address    = var.ses_from_address
  sns_alarm_topic_arn = module.observability.alarms_topic_arn
}

# ---------------------------------------------------------------------------
# api-lambdas: las 19 funciones que expondra API Gateway. Depende de
# dynamodb (tabla) y del bucket de imagenes, no de stream-consumers.
# ---------------------------------------------------------------------------
module "api_lambdas" {
  source = "../../modules/api-lambdas"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner

  dynamodb_table_name = module.dynamodb.dynamodb_table_name
  dynamodb_table_arn  = module.dynamodb.dynamodb_table_arn
  images_bucket_arn   = module.storage.images_bucket_arn
  images_bucket_name  = module.storage.images_bucket_name

  lambda_code_bucket = module.storage.lambda_code_bucket_name
  lambda_code_prefix = "api"
}

# ---------------------------------------------------------------------------
# cognito: autenticacion. No depende de ningun otro modulo propio; es
# consumido por api-gateway (JWT authorizer) y, en el futuro, por el SPA
# directamente para el Hosted UI.
#
# callback_urls/logout_urls se pasan como VARIABLE, no como
# module.storage.cloudfront_domain_name. Hacerlo asi cerraria un ciclo
# real: storage.cloudfront depende de api_gateway_endpoint, api_gateway
# depende de los IDs de cognito, y cognito dependeria del dominio de
# storage -> storage -> cognito -> api_gateway -> storage. Terraform
# rechazaria el plan por ciclo.
#
# Bootstrap en dos fases, documentado tambien en el README de despliegue:
#   1) terraform apply con el valor por defecto (placeholder/localhost).
#   2) terraform output cloudfront_domain_name
#   3) actualizar var.callback_urls / var.logout_urls / var.cors_allowed_origins
#      con ese dominio real y volver a aplicar (solo actualiza el cliente
#      de Cognito y el CORS de API Gateway, no recrea nada).
# ---------------------------------------------------------------------------
module "cognito" {
  source = "../../modules/cognito"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner

  callback_urls           = var.callback_urls
  logout_urls             = var.logout_urls
  hosted_ui_domain_prefix = var.hosted_ui_domain_prefix

  dynamodb_table_name = module.dynamodb.dynamodb_table_name
  dynamodb_table_arn  = module.dynamodb.dynamodb_table_arn
  lambda_code_bucket  = module.storage.lambda_code_bucket_name

  # ses_source_arn / ses_from_address se dejan sin definir por ahora:
  # Cognito usara su cuota interna de emails hasta que el modulo "ses"
  # exista y se pase la identidad verificada aqui.
}

# ---------------------------------------------------------------------------
# api-gateway: expone las funciones de api-lambdas via HTTP API, con el
# JWT Authorizer de cognito en las rutas auth_required. Depende de
# api-lambdas (routes, invoke_arns, names) y de cognito (user pool /
# client). No depende de stream-consumers.
# ---------------------------------------------------------------------------
module "api_gateway" {
  source = "../../modules/api-gateway"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner
  aws_region   = var.aws_region

  routes                = module.api_lambdas.routes
  function_invoke_arns  = module.api_lambdas.function_invoke_arns
  function_names        = module.api_lambdas.function_names

  cognito_user_pool_id        = module.cognito.user_pool_id
  cognito_user_pool_client_id = module.cognito.user_pool_client_id

  cors_allowed_origins = var.cors_allowed_origins
}

# ---------------------------------------------------------------------------
# security: Web ACL de WAF para CloudFront. No depende de ningun otro
# modulo. Debe instanciarse con el provider alias us_east_1 (ver
# providers.tf) porque scope = CLOUDFRONT solo se acepta en esa region.
# ---------------------------------------------------------------------------
module "security" {
  source = "../../modules/security"
  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner
}

# ---------------------------------------------------------------------------
# storage: S3 (frontend, imagenes, codigo Lambda) + CloudFront. La
# distribucion depende del endpoint de api-gateway (comportamiento
# /api/*) y del Web ACL de security; los buckets no dependen de nada
# externo, por eso api-lambdas y stream-consumers pueden depender de
# ellos sin crear un ciclo (ver nota junto a module.cognito sobre el
# unico ciclo real: callback_urls).
# ---------------------------------------------------------------------------
module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner

  api_gateway_endpoint        = module.api_gateway.api_endpoint
  images_cors_allowed_origins = var.cors_allowed_origins
  waf_web_acl_arn             = module.security.web_acl_arn
}

# ---------------------------------------------------------------------------
# observability: log groups + alarmas + topic SNS. Depende de
# api_lambdas, stream_consumers, api_gateway y dynamodb (para los
# nombres/IDs sobre los que alarmar). A su vez, stream_consumers depende
# del topic de este modulo (sns_alarm_topic_arn, arriba). No es un ciclo:
# son recursos distintos dentro de cada modulo (aws_sns_topic.alarms no
# depende de nada; aws_cloudwatch_log_group/metric_alarm si dependen de
# los nombres de funcion) -- mismo principio ya visto con storage.
# ---------------------------------------------------------------------------
locals {
  all_lambda_function_names = merge(
    module.api_lambdas.function_names,
    {
      fan_out                  = module.stream_consumers.fan_out_function_name
      notifications             = module.stream_consumers.notifications_function_name
      cognito_pre_signup        = module.cognito.pre_signup_function_name
      cognito_post_confirmation = module.cognito.post_confirmation_function_name
    }
  )
}

module "observability" {
  source = "../../modules/observability"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner

  lambda_function_names = local.all_lambda_function_names
  api_gateway_id         = module.api_gateway.api_id
  dynamodb_table_name   = module.dynamodb.dynamodb_table_name

  alarm_email = var.alarm_email
}
