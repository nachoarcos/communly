locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Owner       = var.owner
  }
}

# Sin dependencia de var.lambda_function_names: se crea antes que las
# alarmas por funcion, y es lo que stream-consumers necesita para sus
# propias alarmas de DLQ sin generar un ciclo (mismo principio que
# modules/storage: el grafo de Terraform es por recurso, no por modulo).
resource "aws_sns_topic" "alarms" {
  name = "${local.name_prefix}-alarms"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
  # La confirmacion de la suscripcion llega por email y hay que aceptarla
  # a mano tras el primer apply; Terraform no puede automatizar ese paso.
}
