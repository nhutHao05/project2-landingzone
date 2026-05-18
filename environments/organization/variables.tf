variable "admin_email" {
  type        = string
  description = "Email quan tri goc cua ban (Vi du: lhhao05@gmail.com). Toan bo email kich hoat va OTP cua cac tai khoan con se gui ve day."
}

variable "project_name" {
  type        = string
  description = "Ten du an dung de dat ten cho cac tai khoan va tag tai nguyen"
  default     = "project2-soar"
}

variable "aws_profile" {
  type        = string
  description = "Ten AWS CLI profile tuong ung voi Master Account (chay 'aws configure list-profiles' de xem danh sach)"
  default     = "default"
}

# ==========================================
# Phase 2 Variables (Điền sau khi Phase 1 apply xong)
# ==========================================
variable "devops_account_id" {
  type        = string
  description = "Account ID cua tai khoan DevOps (lay tu output sau khi Phase 1 apply)"
  default     = ""
}

variable "monitor_account_id" {
  type        = string
  description = "Account ID cua tai khoan Monitor (lay tu output sau khi Phase 1 apply)"
  default     = ""
}

variable "enable_sso" {
  type        = bool
  description = "Bat quan ly IAM Identity Center permission sets va assignments. Chi bat sau khi enable IAM Identity Center trong AWS Console."
  default     = false
}

variable "sso_admin_group_id" {
  type        = string
  description = "Identity Store Group ID nhan AdministratorAccess tren 3 accounts."
  default     = ""
}

variable "sso_readonly_group_id" {
  type        = string
  description = "Identity Store Group ID nhan ReadOnlyAccess tren 3 accounts."
  default     = ""
}

variable "enable_org_cloudtrail" {
  type        = bool
  description = "Bat Organization CloudTrail sau khi centralized log bucket o Monitor account da ton tai."
  default     = false
}

variable "centralized_logs_bucket_name" {
  type        = string
  description = "Ten S3 bucket centralized logs trong Monitor account."
  default     = ""
}

variable "org_trail_name" {
  type        = string
  description = "Ten Organization CloudTrail."
  default     = "p2-soar-organization-trail"
}
