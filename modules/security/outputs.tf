output "web_acl_arn" {
  description = "ARN del Web ACL, listo para pasar a modules/storage como waf_web_acl_arn"
  value       = aws_wafv2_web_acl.cloudfront.arn
}
