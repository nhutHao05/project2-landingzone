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

output "devops_email" {
  value       = aws_organizations_account.devops.email
  description = "Email da duoc dang ky cho tai khoan DevOps"
}

output "monitor_email" {
  value       = aws_organizations_account.monitor.email
  description = "Email da duoc dang ky cho tai khoan Monitor"
}
