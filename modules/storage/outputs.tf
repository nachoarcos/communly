output "frontend_bucket_name" {
  value = aws_s3_bucket.frontend.bucket
}

output "images_bucket_name" {
  value = aws_s3_bucket.images.bucket
}

output "images_bucket_arn" {
  value = aws_s3_bucket.images.arn
}

output "lambda_code_bucket_name" {
  value = aws_s3_bucket.lambda_code.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "cloudfront_domain_name" {
  description = "Dominio *.cloudfront.net; sera el dominio publico de Communly hasta que se configure uno propio"
  value       = aws_cloudfront_distribution.this.domain_name
}
