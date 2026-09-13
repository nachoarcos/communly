# ---------------------------------------------------------------------------
# Rol de ejecucion Lambda predefinido del laboratorio. No se crea nada
# aqui, solo se resuelve su ARN (por variable directa o, si no se da,
# buscando por nombre -- requiere iam:GetRole).
# ---------------------------------------------------------------------------
data "aws_iam_role" "student_lambda" {
  count = var.student_lambda_role_arn == null ? 1 : 0
  name  = var.student_lambda_role_name
}

locals {
  lambda_role_arn = coalesce(
    var.student_lambda_role_arn,
    try(data.aws_iam_role.student_lambda[0].arn, null)
  )
}

# ---------------------------------------------------------------------------
# dynamodb: fuente de verdad de todo el dominio. No depende de ningun
# otro modulo. Sin cambios respecto a prod: no crea IAM.
# ---------------------------------------------------------------------------
module "dynamodb" {
  source = "../../modules/dynamodb"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner
}

# ---------------------------------------------------------------------------
# stream-consumers: reacciona a cambios en la tabla (fan-out del feed,
# notificaciones por comentario). shared_execution_role_arn evita crear
# un rol IAM propio para fan-out/notifications.
# ---------------------------------------------------------------------------
module "stream_consumers" {
  source = "../../modules/stream-consumers"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner

  dynamodb_table_name = module.dynamodb.dynamodb_table_name
  dynamodb_table_arn  = module.dynamodb.dynamodb_table_arn
  dynamodb_stream_arn = module.dynamodb.dynamodb_stream_arn

  lambda_code_bucket   = module.storage.lambda_code_bucket_name
  fan_out_s3_key        = "stream-consumers/fan-out.zip"
  notifications_s3_key  = "stream-consumers/notifications.zip"

  ses_from_address    = var.ses_from_address
  sns_alarm_topic_arn = module.observability.alarms_topic_arn

  shared_execution_role_arn    = local.lambda_role_arn
  enable_event_source_mappings = var.enable_stream_triggers
  mock_ses_notifications        = var.mock_ses_notifications
  manage_lambda_code_with_terraform = var.manage_lambda_code_with_terraform
}

# ---------------------------------------------------------------------------
# api-lambdas: mismas 19 funciones que prod. shared_execution_role_arn
# evita crear un rol IAM propio por funcion.
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

  shared_execution_role_arn          = local.lambda_role_arn
  manage_lambda_code_with_terraform = var.manage_lambda_code_with_terraform
}

# ---------------------------------------------------------------------------
# cognito: autenticacion. shared_execution_role_arn evita crear roles
# IAM propios para los triggers pre-signup/post-confirmation.
#
# callback_urls/logout_urls: mismo bootstrap en dos fases que prod (ver
# README), pero en dev normalmente apuntan a localhost sin fase 2.
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

  shared_execution_role_arn          = local.lambda_role_arn
  manage_lambda_code_with_terraform = var.manage_lambda_code_with_terraform
}

# ---------------------------------------------------------------------------
# api-gateway: sin cambios respecto a prod -- no crea roles IAM, solo
# permisos de invocacion (lambda:AddPermission), que no es una accion IAM.
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
# security: Web ACL de WAF. Sin cambios respecto a prod -- no requiere
# IAM, solo permisos wafv2:*. Condicionado a var.enable_waf (por defecto
# true; ponerlo a false si el laboratorio no permite wafv2:* o
# restringe us-east-1 de una forma que bloquee este modulo).
# ---------------------------------------------------------------------------
module "security" {
  count  = var.enable_waf ? 1 : 0
  source = "../../modules/security"
  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner
}

# ---------------------------------------------------------------------------
# storage: sin cambios respecto a prod -- las politicas de bucket y el
# Origin Access Control de CloudFront son recursos de S3/CloudFront, no
# de IAM. waf_web_acl_arn es null si var.enable_waf = false.
# ---------------------------------------------------------------------------
module "storage" {
  source = "../../modules/storage"

  project_name = var.project_name
  environment  = var.environment
  owner        = var.owner

  api_gateway_endpoint        = module.api_gateway.api_endpoint
  images_cors_allowed_origins = var.cors_allowed_origins
  waf_web_acl_arn             = var.enable_waf ? module.security[0].web_acl_arn : null

  manage_frontend_with_terraform  = var.manage_frontend_with_terraform
  # trimsuffix: el invoke_url del stage $default de una HTTP API viene
  # SIEMPRE con barra final ("https://.../"), y nuestras rutas del
  # frontend tambien empiezan por barra ("/me/profile") -- sin quitarla
  # aqui, la concatenacion produce "...//me/profile", que no coincide
  # con ninguna ruta de API Gateway y provoca un fallo de CORS confuso
  # (el preflight no encuentra ruta, no hay cabecera CORS, y el
  # navegador lo reporta como bloqueo CORS en vez de "ruta no encontrada").
  frontend_vite_api_base_url      = trimsuffix(module.api_gateway.api_endpoint, "/")
  frontend_vite_cognito_domain    = "https://${module.cognito.hosted_ui_domain}"
  frontend_vite_cognito_client_id = module.cognito.user_pool_client_id
  frontend_vite_redirect_uri      = var.frontend_build_redirect_uri
  frontend_vite_logout_uri        = var.frontend_build_logout_uri
  aws_cli_profile                 = var.aws_cli_profile
  local_exec_shell                 = var.local_exec_shell
}

# ---------------------------------------------------------------------------
# observability: sin cambios respecto a prod.
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

# ---------------------------------------------------------------------------
# Especifico de dev: amplia (no crea) el rol compartido con los permisos
# que las Lambdas necesitan. iam:PutRolePolicy sobre un rol YA EXISTENTE
# es una accion distinta de iam:CreateRole -- puede estar permitida
# aunque crear roles nuevos no lo este. Si el plan falla aqui, poner
# var.attach_extra_permissions_to_shared_role = false y verificar a mano
# en la consola IAM que studentLambdaExecutionRole ya cubre DynamoDB,
# S3 (bucket de imagenes), SES y SQS -- si no los cubre, las Lambdas
# fallaran en tiempo de ejecucion con AccessDenied, y no hay forma de
# arreglarlo desde Terraform sin este permiso.
# ---------------------------------------------------------------------------
resource "aws_iam_role_policy" "student_lambda_extra_permissions" {
  count = var.attach_extra_permissions_to_shared_role ? 1 : 0

  name = "${var.project_name}-${var.environment}-extra-permissions"
  role = coalesce(var.student_lambda_role_name, "studentLambdaExecutionRole")

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem",
          "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem",
          "dynamodb:TransactWriteItems",
        ]
        Resource = [
          module.dynamodb.dynamodb_table_arn,
          "${module.dynamodb.dynamodb_table_arn}/index/*",
        ]
      },
      {
        Sid    = "DynamoDBStreamsAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeStream", "dynamodb:GetRecords",
          "dynamodb:GetShardIterator", "dynamodb:ListStreams",
        ]
        Resource = module.dynamodb.dynamodb_stream_arn
      },
      {
        Sid      = "ImagesBucketAccess"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${module.storage.images_bucket_arn}/*"
      },
      {
        Sid      = "SESAccess"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Sid      = "SQSDlqAccess"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = "*"
      },
    ]
  })
}
