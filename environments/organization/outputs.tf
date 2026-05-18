# Output Account IDs ngay sau khi Phase 1 apply xong
# Copy các giá trị này vào terraform.tfvars để chạy Phase 2
output "devops_account_id" {
  value       = aws_organizations_account.devops.id
  description = "AWS Account ID cua tai khoan DevOps - Copy vao tfvars de dung Phase 2"
}

output "monitor_account_id" {
  value       = aws_organizations_account.monitor.id
  description = "AWS Account ID cua tai khoan Monitor - Copy vao tfvars de dung Phase 2"
}

output "master_account_id" {
  value       = data.aws_caller_identity.current.account_id
  description = "AWS Account ID cua tai khoan Master"
}

output "organization_id" {
  value       = aws_organizations_organization.org.id
  description = "AWS Organization ID"
}

output "root_id" {
  value       = aws_organizations_organization.org.roots[0].id
  description = "AWS Organizations Root ID"
}

output "devops_email" {
  value       = aws_organizations_account.devops.email
  description = "Email da duoc dang ky cho tai khoan DevOps"
}

output "monitor_email" {
  value       = aws_organizations_account.monitor.email
  description = "Email da duoc dang ky cho tai khoan Monitor"
}

output "workloads_ou_id" {
  value       = aws_organizations_organizational_unit.workloads.id
  description = "OU ID cho workload accounts"
}

output "security_ou_id" {
  value       = aws_organizations_organizational_unit.security.id
  description = "OU ID cho security/monitoring accounts"
}

output "administrator_permission_set_arn" {
  value       = var.enable_sso ? aws_ssoadmin_permission_set.administrator_access[0].arn : null
  description = "SSO AdministratorAccess permission set ARN"
}

output "readonly_permission_set_arn" {
  value       = var.enable_sso ? aws_ssoadmin_permission_set.readonly_access[0].arn : null
  description = "SSO ReadOnlyAccess permission set ARN"
}

output "organization_trail_arn" {
  value       = var.enable_org_cloudtrail ? aws_cloudtrail.organization[0].arn : null
  description = "Organization CloudTrail ARN"
}
