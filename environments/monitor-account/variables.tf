variable "master_account_id" {
  type        = string
  description = "AWS Account ID của Master Account (Management Account)"
}

variable "devops_account_id" {
  type        = string
  description = "AWS Account ID của tài khoản DevOps vừa sinh ra"
}

variable "monitor_account_id" {
  type        = string
  description = "AWS Account ID của tài khoản Monitor vừa sinh ra"
}

variable "project_name" {
  type        = string
  description = "Ten cua du an dung de lam prefix cho S3 Bucket"
  default     = "project2-soar"
}
