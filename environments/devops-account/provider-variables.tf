variable "aws_region" {
  type        = string
  description = "AWS region for the DevOps workload account."
  default     = "ap-southeast-1"
}

variable "aws_profile" {
  type        = string
  description = "AWS CLI profile for the management account used to assume into DevOps."
  default     = "default"
}
