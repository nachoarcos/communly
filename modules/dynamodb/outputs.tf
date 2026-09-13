output "dynamodb_table_name" {
  description = "Nombre de la tabla DynamoDB"
  value       = aws_dynamodb_table.communly.name
}

output "dynamodb_table_arn" {
  description = "ARN de la tabla DynamoDB"
  value       = aws_dynamodb_table.communly.arn
}

output "dynamodb_stream_arn" {
  description = "ARN del DynamoDB Stream"
  value       = aws_dynamodb_table.communly.stream_arn
}

output "dynamodb_gsi1_name" {
  value = "GSI1"
}

output "dynamodb_gsi2_name" {
  value = "GSI2"
}
