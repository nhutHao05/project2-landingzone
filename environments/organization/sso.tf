locals {
  sso_account_ids = toset([
    data.aws_caller_identity.current.account_id,
    aws_organizations_account.devops.id,
    aws_organizations_account.monitor.id
  ])

  sso_admin_enabled    = var.enable_sso && var.sso_admin_group_id != ""
  sso_readonly_enabled = var.enable_sso && var.sso_readonly_group_id != ""
}

data "aws_ssoadmin_instances" "current" {
  count = var.enable_sso ? 1 : 0
}

resource "aws_ssoadmin_permission_set" "administrator_access" {
  count            = var.enable_sso ? 1 : 0
  name             = "AdministratorAccess"
  description      = "Full administrator access for landing zone administrators."
  instance_arn     = data.aws_ssoadmin_instances.current[0].arns[0]
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "administrator_access" {
  count              = var.enable_sso ? 1 : 0
  instance_arn       = data.aws_ssoadmin_instances.current[0].arns[0]
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  permission_set_arn = aws_ssoadmin_permission_set.administrator_access[0].arn
}

resource "aws_ssoadmin_account_assignment" "administrator_access" {
  for_each           = local.sso_admin_enabled ? local.sso_account_ids : toset([])
  instance_arn       = data.aws_ssoadmin_instances.current[0].arns[0]
  permission_set_arn = aws_ssoadmin_permission_set.administrator_access[0].arn
  principal_id       = var.sso_admin_group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}

resource "aws_ssoadmin_permission_set" "readonly_access" {
  count            = var.enable_sso ? 1 : 0
  name             = "ReadOnlyAccess"
  description      = "Read-only access for landing zone reviewers."
  instance_arn     = data.aws_ssoadmin_instances.current[0].arns[0]
  session_duration = "PT4H"
}

resource "aws_ssoadmin_managed_policy_attachment" "readonly_access" {
  count              = var.enable_sso ? 1 : 0
  instance_arn       = data.aws_ssoadmin_instances.current[0].arns[0]
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
  permission_set_arn = aws_ssoadmin_permission_set.readonly_access[0].arn
}

resource "aws_ssoadmin_account_assignment" "readonly_access" {
  for_each           = local.sso_readonly_enabled ? local.sso_account_ids : toset([])
  instance_arn       = data.aws_ssoadmin_instances.current[0].arns[0]
  permission_set_arn = aws_ssoadmin_permission_set.readonly_access[0].arn
  principal_id       = var.sso_readonly_group_id
  principal_type     = "GROUP"
  target_id          = each.value
  target_type        = "AWS_ACCOUNT"
}
