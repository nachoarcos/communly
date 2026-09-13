locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
  }
}

resource "aws_cognito_user_pool" "this" {
  name = "${local.name_prefix}-users"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length    = 10
    require_lowercase = true
    require_uppercase = true
    require_numbers   = true
    require_symbols   = false # 10 caracteres + mayus/minus/numeros es un compromiso razonable de UX/seguridad para este proyecto
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Evita que los mensajes de error revelen si un email ya esta registrado
  # (mitigacion estandar contra enumeracion de usuarios).
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  dynamic "email_configuration" {
    for_each = var.ses_source_arn == null ? [] : [1]
    content {
      email_sending_account = "DEVELOPER"
      source_arn            = var.ses_source_arn
      from_email_address    = var.ses_from_address
    }
  }

  # Cognito con username_attributes=["email"] no tiene ningun campo
  # nativo para un nombre de usuario publico (el username interno lo
  # genera Cognito, ilegible). Se anade como atributo custom, elegido
  # por el usuario en el registro.
  #
  # required=false es una restriccion dura de AWS: los atributos custom
  # NUNCA pueden ser "required" a nivel de esquema. La obligatoriedad
  # real se impone en el trigger Pre Sign-up (ver triggers.tf), que
  # rechaza el registro si falta.
  schema {
    name                     = "username"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = false
    required                 = false

    string_attribute_constraints {
      min_length = 3
      max_length = 30
    }
  }

  lambda_config {
    pre_sign_up         = aws_lambda_function.pre_signup.arn
    post_confirmation   = aws_lambda_function.post_confirmation.arn
  }

  # Proteccion contra destroy accidental: activa solo en prod. Borrar el
  # User Pool en produccion invalida todas las sesiones y credenciales
  # de todos los usuarios registrados.
  deletion_protection = var.environment == "prod" ? "ACTIVE" : "INACTIVE"

  tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
  }
}
