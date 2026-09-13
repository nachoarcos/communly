output "function_arns" {
  description = "Mapa access_pattern -> ARN de la funcion Lambda"
  value       = { for k, f in aws_lambda_function.this : k => f.arn }
}

output "function_names" {
  description = "Mapa access_pattern -> nombre de la funcion Lambda"
  value       = { for k, f in aws_lambda_function.this : k => f.function_name }
}

output "function_invoke_arns" {
  description = "Mapa access_pattern -> invoke ARN (lo necesita el modulo api-gateway para la integracion)"
  value       = { for k, f in aws_lambda_function.this : k => f.invoke_arn }
}

output "routes" {
  description = "Metadatos de enrutado que consume el modulo api-gateway: metodo, path, si requiere auth y si es solo admin"
  value = {
    for k, f in local.functions : k => {
      method        = f.http_method
      path          = f.http_path
      auth_required = f.auth_required
      admin_only    = f.admin_only
      function_key  = k
    }
  }
}
