terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # SIN bloque "backend": este es precisamente el Terraform que crea el
  # backend remoto que usara todo lo demas. El estado de bootstrap vive
  # en local (terraform.tfstate junto a estos ficheros). No contiene
  # secretos, pero SI contiene ARNs sensibles: no se sube al repositorio
  # (anadir terraform.tfstate* al .gitignore) y conviene copiarlo a un
  # sitio seguro tras aplicarlo, porque es el unico estado del proyecto
  # que no esta protegido por el propio bucket que crea.
}

provider "aws" {
  region = var.aws_region
}
