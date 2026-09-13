terraform {
  backend "s3" {
    bucket         = "communly-tfstate-<cuenta>"
    key            = "envs/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "communly-tfstate-locks"
    encrypt        = true
  }
}
