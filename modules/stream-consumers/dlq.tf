resource "aws_sqs_queue" "fan_out_dlq" {
  name                      = "${local.name_prefix}-fan-out-dlq"
  message_retention_seconds = 1209600 # 14 dias: tiempo maximo para investigar/reprocesar
  sqs_managed_sse_enabled   = true
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "notifications_dlq" {
  name                      = "${local.name_prefix}-notifications-dlq"
  message_retention_seconds = 1209600
  sqs_managed_sse_enabled   = true
  tags                      = local.common_tags
}

# Observabilidad minima: alarma si algo llega a cualquiera de las dos DLQ.
# Un mensaje en la DLQ significa que el fan-out o la notificacion de ese
# evento se ha perdido y requiere intervencion manual.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  for_each = {
    fan_out       = aws_sqs_queue.fan_out_dlq.name
    notifications = aws_sqs_queue.notifications_dlq.name
  }

  alarm_name          = "${local.name_prefix}-${each.key}-dlq-messages"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Hay eventos de ${each.key} que han agotado los reintentos y estan en la DLQ."

  dimensions = {
    QueueName = each.value
  }

  alarm_actions = [var.sns_alarm_topic_arn]
  ok_actions    = [var.sns_alarm_topic_arn]
  tags          = local.common_tags
}
