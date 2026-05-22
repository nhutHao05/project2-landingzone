# ==========================================
# 📬 SQS QUEUE — Nhận S3 Event Notification
# ==========================================
# Mỗi khi CloudTrail ghi 1 file log mới vào S3 →
# S3 gửi message vào queue này →
# Elastic Agent poll queue để biết có file mới cần đọc
# ==========================================

resource "aws_sqs_queue" "cloudtrail_notifications" {
  name                       = "${var.project_name}-cloudtrail-notifications"
  message_retention_seconds  = 86400 # Giữ message 1 ngày nếu Agent chưa đọc kịp
  visibility_timeout_seconds = 300   # Agent có 5 phút để xử lý 1 message

  tags = {
    Name = "${var.project_name}-cloudtrail-notifications"
  }
}

# ==========================================
# 🔐 SQS QUEUE POLICY
# Cho phép S3 Bucket gửi message vào SQS queue
# ==========================================
resource "aws_sqs_queue_policy" "cloudtrail_notifications" {
  queue_url = aws_sqs_queue.cloudtrail_notifications.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ToSendMessage"
        Effect = "Allow"
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.cloudtrail_notifications.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.centralized_logs.arn
          }
        }
      }
    ]
  })
}

# ==========================================
# 🔔 S3 EVENT NOTIFICATION → SQS
# Mỗi khi có file .json.gz mới trong AWSLogs/ → gửi notification
# ==========================================
resource "aws_s3_bucket_notification" "cloudtrail_to_sqs" {
  bucket = aws_s3_bucket.centralized_logs.id

  queue {
    queue_arn     = aws_sqs_queue.cloudtrail_notifications.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "AWSLogs/" # Chỉ theo dõi thư mục CloudTrail logs
    filter_suffix = ".json.gz" # Chỉ theo dõi file log (không trigger với folder)
  }

  depends_on = [aws_sqs_queue_policy.cloudtrail_notifications]
}

# ==========================================
# 📤 OUTPUTS — Dùng khi cấu hình Elastic Integration
# ==========================================
output "sqs_queue_url" {
  value       = aws_sqs_queue.cloudtrail_notifications.url
  description = "SQS Queue URL — Dien vao Elastic AWS CloudTrail Integration"
}

output "sqs_queue_arn" {
  value       = aws_sqs_queue.cloudtrail_notifications.arn
  description = "SQS Queue ARN"
}
