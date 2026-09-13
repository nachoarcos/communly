resource "aws_cognito_user_pool_client" "web" {
  name         = "${local.name_prefix}-web-client"
  user_pool_id = aws_cognito_user_pool.this.id

  # Cliente publico: sin secreto (SPA, no hay forma de proteger un
  # client_secret en codigo que corre en el navegador)
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"] # Authorization Code + PKCE
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = ["COGNITO"]

  callback_urls = var.callback_urls
  logout_urls   = var.logout_urls

  # Sin esto, el SDK del cliente no puede enviar custom:username en el
  # registro ni leerlo despues: los atributos custom no se incluyen por
  # defecto, hay que listarlos explicitamente.
  read_attributes  = ["email", "custom:username"]
  write_attributes = ["email", "custom:username"]

  # No revela si el email/usuario existe ante intentos de login fallidos
  prevent_user_existence_errors = "ENABLED"

  access_token_validity  = 1
  id_token_validity      = 1
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}
