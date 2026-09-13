terraform {
  backend "s3" {
    bucket         = "communly-tfstate-537595753912"
    key            = "envs/dev/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "communly-tfstate-locks"
    encrypt        = true
  }
}
