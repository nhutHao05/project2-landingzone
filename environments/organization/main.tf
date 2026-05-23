terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ==========================================
# 👑 MASTER ACCOUNT PROVIDER (DEFAULT)
# ==========================================
provider "aws" {
  region  = "ap-southeast-1"
  profile = var.aws_profile
}

# Identity data source để lấy Master Account ID động
data "aws_caller_identity" "current" {}

# ==========================================
# 📧 2. DYNAMIC EMAIL ALIASING (LOCALS)
# ==========================================
locals {
  # Tach email goc: "prefix@domain.com"
  email_parts  = split("@", var.admin_email)
  email_prefix = local.email_parts[0]
  email_domain = local.email_parts[1]

  # Tu dong ghep email alias doc nhat vo nhi cho tung account con
  devops_email  = "${local.email_prefix}+${var.project_name}-devops@${local.email_domain}"
  monitor_email = "${local.email_prefix}+${var.project_name}-monitor@${local.email_domain}"
}

# ==========================================
# 🏢 3. KHỞI TẠO AWS ORGANIZATIONS & ACCOUNTS
# ==========================================
resource "aws_organizations_organization" "org" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "sso.amazonaws.com"
  ]
  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
  feature_set          = "ALL"
}

resource "aws_organizations_account" "devops" {
  name              = "${var.project_name}-DevOps-Account"
  email             = local.devops_email
  parent_id         = aws_organizations_organizational_unit.workloads.id
  role_name         = "OrganizationAccountAccessRole"
  close_on_deletion = true

  depends_on = [aws_organizations_organizational_unit.workloads]
}

resource "aws_organizations_account" "monitor" {
  name              = "${var.project_name}-Monitor-Account"
  email             = local.monitor_email
  parent_id         = aws_organizations_organizational_unit.security.id
  role_name         = "OrganizationAccountAccessRole"
  close_on_deletion = true

  depends_on = [aws_organizations_organizational_unit.security]
}

resource "aws_organizations_organizational_unit" "workloads" {
  name      = "Workloads"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "security" {
  name      = "Security"
  parent_id = aws_organizations_organization.org.roots[0].id
}

# ==========================================
# 🔒 4. SERVICE CONTROL POLICY (SCPs)
# ==========================================
resource "aws_organizations_policy" "restrict_region" {
  depends_on  = [aws_organizations_organization.org]
  name        = "Restrict-Region-Policy"
  description = "Chi cho phep trien khai tai nguyen tai Singapore de tiet kiem chi phi"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyAllOutsideSingapore"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "organizations:*",
          "route53:*",
          "support:*",
          "sts:*",
          "sso:*",
          "budgets:*",
          "ec2:DescribeRegions",
          "ec2:DescribeAvailabilityZones",
          "aws-marketplace:*",
          "bedrock:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = ["ap-southeast-1"]
          }
        }
      }
    ]
  })
}

# Gán SCP vào Root Organization để bảo vệ toàn diện các accounts con
resource "aws_organizations_policy_attachment" "root_restrict_region" {
  policy_id = aws_organizations_policy.restrict_region.id
  target_id = aws_organizations_organization.org.roots[0].id
}
