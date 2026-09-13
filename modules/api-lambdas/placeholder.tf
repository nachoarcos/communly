# aws_lambda_function exige que el objeto en s3_key exista en el momento
# del apply. Antes de que el pipeline de la app haya subido ningun .zip
# real, este placeholder evita que el primer apply falle por "objeto no
# encontrado". Una vez el pipeline sube el codigo real a la misma key,
# Terraform no lo vuelve a pisar (ver ignore_changes).

terraform {
  required_providers {
    archive = {
      source = "hashicorp/archive"
    }
  }
}

data "archive_file" "placeholder" {
  type        = "zip"
  output_path = "${path.module}/.placeholder.zip"

  source {
    content  = "exports.handler = async () => ({ statusCode: 501, body: 'not deployed yet' });"
    filename = "index.js"
  }
}

resource "aws_s3_object" "placeholder" {
  # Innecesario si Terraform sube el codigo directamente (ver archive.tf).
  # Mismo motivo que en archive.tf: se itera sobre las claves (toset),
  # no sobre local.functions directamente, para evitar el error de
  # unificacion de tipos de HCL en el condicional.
  for_each = var.manage_lambda_code_with_terraform ? toset([]) : toset(keys(local.functions))

  bucket = var.lambda_code_bucket
  key    = "${var.lambda_code_prefix}/${each.key}.zip"
  source = data.archive_file.placeholder.output_path
  etag   = data.archive_file.placeholder.output_md5

  lifecycle {
    ignore_changes = [etag, source]
  }
}
