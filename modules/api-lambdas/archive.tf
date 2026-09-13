# Solo se usa cuando var.manage_lambda_code_with_terraform = true. Cada
# zip incluye el index.py de la funcion mas todo shared/*.py, sin pasar
# por S3 ni por ningun pipeline externo -- pensado para entornos sin
# CI/CD (dev, despliegue manual).
locals {
  shared_files = fileset("${path.module}/../../app/lambdas/shared", "**/*.py")
}

data "archive_file" "source" {
  # Se itera sobre las CLAVES (toset), no sobre local.functions
  # directamente: local.functions es un mapa de objetos donde cada
  # entrada tiene una lista "statements" de distinta longitud, y HCL no
  # consigue unificar el tipo entre las dos ramas de un condicional
  # (? local.functions : {}) cuando los objetos del mapa no son todos
  # identicos en forma. Con un set de strings no hay ese problema.
  for_each = var.manage_lambda_code_with_terraform ? toset(keys(local.functions)) : toset([])

  type        = "zip"
  output_path = "${path.module}/dist-${each.key}.zip"

  source {
    content  = file("${path.module}/../../app/lambdas/${each.key}/index.py")
    filename = "index.py"
  }

  dynamic "source" {
    for_each = local.shared_files
    content {
      content  = file("${path.module}/../../app/lambdas/shared/${source.value}")
      filename = "shared/${source.value}"
    }
  }
}
