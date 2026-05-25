variable "project" {
  type        = string
  description = "name of the project"
}

variable "env" {
  type        = string
  description = "environments apply on the vpc (valid values: dev, staging, prod)"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.env)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "region_short" {
  type        = string
  description = "region of subnet provide short form for region Ex: ap-southeast-1 → apse1"
  default     = "apse1"
}

variable "vpc_cidr" {
  type        = string
  description = "range of ip/subnet of vpc for this project use (\"10.0.0.0/16)"
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "list of public ip/subnet for this project ([\"10.0.1.0/24\", \"10.0.2.0/24\", \"10.0.3.0/24\"])"
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "list of private ip/subnet use inside vpc for this project ([\"10.0.4.0/24\", \"10.0.5.0/24\", \"10.0.6.0/24\"])"
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "db_subnet_cidrs" {
  type        = list(string)
  description = "list of ip/private use for database for this project ([\"10.0.7.0/24\", \"10.0.8.0/24\", \"10.0.9.0/24\"])"
  default     = ["10.0.7.0/24", "10.0.8.0/24", "10.0.9.0/24"]
}

variable "enable_nat_gateway" {
  type    = bool
  default = false
  #   terraform destroy -target=aws_nat_gateway.main -target=aws_eip.nat => tat NAT
  #   terraform apply -var="enable_nat_gateway=true" => bat nat
}

variable "db_username" {
  type    = string
  default = "admin"
}

variable "app_db_name" {
  type        = string
  description = "Database name used by the web application in the layer 3 RDS instance"
  default     = "opsdesk"
}

variable "app_ssm_prefix" {
  type        = string
  description = "SSM prefix for web application database connection settings"
  default     = "/webapp"
}

variable "monitor_account_id" {
  type        = string
  description = "AWS Account ID của tài khoản Monitor để đẩy logs"
}

variable "devops_account_id" {
  type        = string
  description = "AWS Account ID của tài khoản DevOps để assume role"
  default     = ""
}

variable "monitor_remediation_lambda_role_name" {
  type        = string
  description = "Ten IAM role cua Monitor remediation Lambda duoc phep assume role remediate ben DevOps"
  default     = "p2-soar-remediation-lambda-role"
}
