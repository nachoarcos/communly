terraform {
  backend "s3" {
    bucket         = "communly-tfstate-<cuenta>"
    key            = "envs/prod/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "communly-tfstate-locks"
    encrypt        = true
  }
}
