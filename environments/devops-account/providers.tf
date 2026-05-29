provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  assume_role {
    role_arn     = "arn:aws:iam::${var.devops_account_id}:role/OrganizationAccountAccessRole"
    session_name = "TerraformDevOpsDeployment"
  }

  default_tags {
    tags = merge(
      {
        Project     = var.project
        Environment = var.env
        ManagedBy   = "Terraform"
      },
      var.tags
    )
  }
}
