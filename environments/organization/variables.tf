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
