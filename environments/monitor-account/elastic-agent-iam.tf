# ==========================================
# 👤 IAM USER — Dành riêng cho Elastic Agent
# ==========================================
# Elastic Agent cần credentials để:
#   - Đọc file log từ S3 bucket
#   - Poll và xóa messages từ SQS queue
# Tạo 1 user riêng với quyền tối thiểu (Least Privilege)
# ==========================================

resource "aws_iam_user" "elastic_agent" {
  name = "${var.project_name}-elastic-agent"
  path = "/service-accounts/"

  tags = {
    Name        = "${var.project_name}-elastic-agent"
    Description = "Service account for Elastic Agent to read CloudTrail logs from S3/SQS"
  }
}

resource "aws_iam_access_key" "elastic_agent" {
  user = aws_iam_user.elastic_agent.name
}

# ==========================================
# 🔐 IAM POLICY — Quyền tối thiểu cho Elastic Agent
# ==========================================
resource "aws_iam_user_policy" "elastic_agent" {
  name = "${var.project_name}-elastic-agent-policy"
  user = aws_iam_user.elastic_agent.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Quyền đọc file log từ S3 bucket
        Sid    = "AllowS3ReadCloudTrailLogs"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.centralized_logs.arn,
          "${aws_s3_bucket.centralized_logs.arn}/*"
        ]
      },
      {
        # Quyền poll và xử lý message từ SQS queue
        Sid    = "AllowSQSProcessNotifications"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.cloudtrail_notifications.arn
      }
    ]
  })
}

# ==========================================
# 📤 OUTPUTS — Sensitive: Dùng khi cấu hình Elastic Integration
# ==========================================
output "elastic_agent_access_key_id" {
  value       = aws_iam_access_key.elastic_agent.id
  description = "IAM Access Key ID cho Elastic Agent — Dien vao Elastic AWS Integration"
  sensitive   = false # Key ID không cần giấu (không đăng nhập được nếu không có secret)
}

output "elastic_agent_secret_access_key" {
  value       = aws_iam_access_key.elastic_agent.secret
  description = "IAM Secret Access Key cho Elastic Agent — BAO MAT, khong commit len git"
  sensitive   = true # Giấu trong terminal, xem bằng: terraform output -raw elastic_agent_secret_access_key
}
