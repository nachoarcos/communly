output "alarms_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "lambda_log_group_names" {
  value = { for k, lg in aws_cloudwatch_log_group.lambda : k => lg.name }
}
