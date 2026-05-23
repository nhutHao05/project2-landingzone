terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket = "p1-bootstrap-apse1-tfstate"
    key    = "devops-account/terraform.tfstate"
    region = "ap-southeast-1"
  }
}
