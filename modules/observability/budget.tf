# AWS Budgets: servicio global de facturacion (como IAM, no esta ligado
# a la region del provider). Un unico presupuesto mensual con dos
# umbrales de aviso -- no se filtra por tag de proyecto porque, en un
# laboratorio de formacion dedicado a este ejercicio, el presupuesto ya
# cubre toda la cuenta de forma razonable; en una cuenta compartida
# entre varios proyectos, aqui convendria anadir un cost_filter por tag.
resource "aws_budgets_budget" "monthly_cost" {
  count = var.enable_budget ? 1 : 0

  name         = "${local.name_prefix}-monthly-cost"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  # Aviso temprano: el gasto REAL acumulado ya supera el 80% del limite.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alarm_email]
  }

  # Aviso previsor: AWS Cost Explorer PREVE que, al ritmo actual, se
  # superara el 100% del limite antes de que acabe el mes -- llega
  # antes que el aviso de gasto real, da tiempo a reaccionar.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alarm_email]
  }
}
