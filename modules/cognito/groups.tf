resource "aws_cognito_user_pool_group" "admins" {
  name         = "admins"
  user_pool_id = aws_cognito_user_pool.this.id
  description  = "Usuarios con acceso al panel de moderacion (list_moderation_queue, resolve_report)"
  precedence   = 1
}

# Nota de operacion, no de Terraform: convertir a un usuario en admin es
# una accion manual/administrativa deliberadamente fuera de este modulo:
#
#   aws cognito-idp admin-add-user-to-group \
#     --user-pool-id <user_pool_id> \
#     --username <email-o-sub> \
#     --group-name admins
#
# Igual que no gestionarias altas de empleados con IaC, no tiene sentido
# versionar "quien es admin hoy" como estado declarativo de Terraform.
