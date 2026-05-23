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

# ==========================================
# Phase 2 Variables — Elastic Agent EC2
# ==========================================
variable "enable_elastic_agent_ec2" {
  type        = bool
  description = "Bat/tat viec tao EC2 cho Elastic Agent. Bat sau khi lay Fleet URL va Enrollment Token tu Kibana."
  default     = false
}

variable "elastic_fleet_url" {
  type        = string
  description = "Fleet Server URL lay tu Kibana → Fleet → Settings. Vi du: https://elastic.hungcx.cloud:8220"
  default     = ""
}

variable "elastic_enrollment_token" {
  type        = string
  description = "Enrollment Token lay tu Kibana → Fleet → Agents → Add agent → chon policy p2-soar-aws-policy"
  sensitive   = true
  default     = ""
}

# ==========================================
# Phase 3 Variables — AI Engine
# ==========================================
variable "elasticsearch_url" {
  type        = string
  description = "URL cua Elasticsearch cluster"
  default     = "https://elastic.hungcx.cloud:9200"
}

variable "elasticsearch_username" {
  type        = string
  description = "Username de Lambda truy van Elasticsearch (VD: haonh)"
  default     = "haonh"
}

variable "elasticsearch_password" {
  type        = string
  description = "Password truy van Elasticsearch"
  sensitive   = true
}

variable "bedrock_model_id" {
  type        = string
  description = "Model ID dung tren Amazon Bedrock"
  default     = "anthropic.claude-3-haiku-20240307-v1:0"
}

variable "bedrock_region" {
  type        = string
  description = "AWS region for Amazon Bedrock API calls"
  default     = "us-east-1"
}

variable "telegram_bot_token" {
  type        = string
  description = "Telegram Bot Token (from @BotFather)"
  sensitive   = true
  default     = ""
}

variable "telegram_chat_id" {
  type        = string
  description = "Telegram Chat ID to send alerts"
  default     = ""
}
