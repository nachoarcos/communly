# Este fichero es el unico del proyecto que usa un provisioner
# local-exec -- una excepcion deliberada, no el patron habitual. A
# diferencia del codigo de las Lambdas (empaquetado con archive_file,
# un mecanismo nativo de Terraform que no ejecuta nada externo),
# "npm run build" es un paso de compilacion arbitrario que ningun
# recurso de ningun proveedor sabe hacer. local-exec es la unica
# herramienta que Terraform ofrece para esto, y la propia documentacion
# de HashiCorp la describe como ultimo recurso: ejecuta un comando de
# shell arbitrario en la maquina donde corre "terraform apply", lo cual
# rompe parte del modelo declarativo normal (Terraform no sabe lo que
# hace el comando, solo si se ha ejecutado o no segun los triggers).
#
# Requisitos para que esto funcione: node/npm y aws cli instalados y en
# el PATH de la maquina que ejecuta terraform apply, con credenciales
# validas ya activas en esa misma sesion (aws sso login, etc.) -- el
# local-exec hereda el entorno del proceso de Terraform, no gestiona
# autenticacion por si mismo.

locals {
  frontend_src_files = var.manage_frontend_with_terraform ? fileset("${path.module}/../../app/frontend/src", "**") : []

  # Hash del CODIGO FUENTE (no del build): asi el rebuild se dispara
  # solo cuando cambia algo real en src/, index.html, package.json o
  # vite.config.js -- no en cada apply.
  frontend_source_hash = var.manage_frontend_with_terraform ? sha1(join("", concat(
    [for f in local.frontend_src_files : filesha1("${path.module}/../../app/frontend/src/${f}")],
    [filesha1("${path.module}/../../app/frontend/index.html")],
    [filesha1("${path.module}/../../app/frontend/package.json")],
    [filesha1("${path.module}/../../app/frontend/vite.config.js")],
  ))) : ""

  aws_cli_profile_flag = var.aws_cli_profile != "" ? " --profile ${var.aws_cli_profile}" : ""

  # cmd.exe (Windows) no expande '*' como comodin antes de pasarlo al
  # programa -- ahi NO hacen falta comillas, y de hecho anadirlas rompe
  # el parseo de comillas anidadas de cmd.exe cuando el comando entero
  # ya va envuelto en "cmd /C \"...\"" (comportamiento inconsistente
  # conocido de cmd.exe, no un bug de Terraform). En bash/sh, sin
  # comillas, la propia shell expandiria "/*" contra el sistema de
  # ficheros real -- ahi si hacen falta (comillas simples).
  invalidation_paths_arg = var.local_exec_shell == "windows" ? "/*" : "'/*'"
}

resource "null_resource" "frontend_deploy" {
  count = var.manage_frontend_with_terraform ? 1 : 0

  triggers = {
    # Se reconstruye y se vuelve a desplegar si cambia el codigo fuente
    # O si cambia cualquiera de las variables VITE_* (por ejemplo, al
    # pasar de apuntar a localhost a apuntar al dominio real de
    # CloudFront en la fase 2 del bootstrap) O si cambia el bucket/la
    # distribucion (recreacion de storage).
    source_hash = local.frontend_source_hash
    env_hash = sha1(join("|", [
      var.frontend_vite_api_base_url,
      var.frontend_vite_cognito_domain,
      var.frontend_vite_cognito_client_id,
      var.frontend_vite_redirect_uri,
      var.frontend_vite_logout_uri,
    ]))
    bucket_name     = aws_s3_bucket.frontend.id
    distribution_id = aws_cloudfront_distribution.this.id
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/../../app/frontend"

    environment = {
      VITE_API_BASE_URL      = var.frontend_vite_api_base_url
      VITE_COGNITO_DOMAIN    = var.frontend_vite_cognito_domain
      VITE_COGNITO_CLIENT_ID = var.frontend_vite_cognito_client_id
      VITE_REDIRECT_URI      = var.frontend_vite_redirect_uri
      VITE_LOGOUT_URI        = var.frontend_vite_logout_uri
    }

    # Una sola cadena de comandos: build, sync y invalidacion. Si
    # cualquiera falla, la cadena se detiene (&& de por medio) y
    # Terraform marca el recurso como fallido -- igual que fallaria un
    # despliegue manual en el mismo punto.
    command = join(" && ", [
      "npm install",
      "npm run build",
      "aws s3 sync dist s3://${aws_s3_bucket.frontend.id} --delete${local.aws_cli_profile_flag}",
      "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.this.id} --paths ${local.invalidation_paths_arg}${local.aws_cli_profile_flag}",
    ])
  }

  depends_on = [aws_cloudfront_distribution.this, aws_s3_bucket_policy.frontend]
}
