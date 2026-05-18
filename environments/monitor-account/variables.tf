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

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile cua Management Account dung de assume role vao Monitor Account"
  default     = "default"
}

variable "aws_region" {
  type        = string
  description = "AWS region dung cho landing zone"
  default     = "ap-southeast-1"
}

variable "organization_id" {
  type        = string
  description = "AWS Organization ID dung cho Organization CloudTrail bucket policy"
}

variable "org_trail_name" {
  type        = string
  description = "Ten Organization CloudTrail o Management Account"
  default     = "p2-soar-organization-trail"
}
