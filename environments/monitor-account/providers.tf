terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  assume_role {
    role_arn     = "arn:aws:iam::${var.monitor_account_id}:role/OrganizationAccountAccessRole"
    session_name = "TerraformMonitorDeployment"
  }

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = "security"
      ManagedBy   = "Terraform"
    }
  }
}
