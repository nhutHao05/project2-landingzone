# ==========================================
# 📬 SQS QUEUES — Nhận S3 Event Notification
# ==========================================

# 1. CloudTrail Notifications Queue
resource "aws_sqs_queue" "cloudtrail_notifications" {
  name                       = "${var.project_name}-cloudtrail-notifications"
  message_retention_seconds  = 86400 # Giữ message 1 ngày
  visibility_timeout_seconds = 300   # Agent có 5 phút để xử lý 1 message

  tags = {
    Name = "${var.project_name}-cloudtrail-notifications"
  }
}

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

# 2. VPC Flow Logs Notifications Queue
resource "aws_sqs_queue" "vpcflow_notifications" {
  name                       = "${var.project_name}-vpcflow-notifications"
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 300

  tags = {
    Name = "${var.project_name}-vpcflow-notifications"
  }
}

resource "aws_sqs_queue_policy" "vpcflow_notifications" {
  queue_url = aws_sqs_queue.vpcflow_notifications.id

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
        Resource = aws_sqs_queue.vpcflow_notifications.arn
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.centralized_logs.arn
          }
        }
      }
    ]
  })
}

# 3. ALB Access Logs Notifications Queue
resource "aws_sqs_queue" "alb_notifications" {
  name                       = "${var.project_name}-alb-notifications"
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 300

  tags = {
    Name = "${var.project_name}-alb-notifications"
  }
}

resource "aws_sqs_queue_policy" "alb_notifications" {
  queue_url = aws_sqs_queue.alb_notifications.id

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
        Resource = aws_sqs_queue.alb_notifications.arn
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
# ==========================================
resource "aws_s3_bucket_notification" "cloudtrail_to_sqs" {
  bucket = aws_s3_bucket.centralized_logs.id

  queue {
    queue_arn     = aws_sqs_queue.cloudtrail_notifications.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "AWSLogs/"
    filter_suffix = ".json.gz"
  }

  queue {
    queue_arn     = aws_sqs_queue.vpcflow_notifications.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "vpc-flowlogs/"
    filter_suffix = ".log.gz"
  }

  queue {
    queue_arn     = aws_sqs_queue.alb_notifications.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "alb-logs/"
    filter_suffix = ".log.gz"
  }

  depends_on = [
    aws_sqs_queue_policy.cloudtrail_notifications,
    aws_sqs_queue_policy.vpcflow_notifications,
    aws_sqs_queue_policy.alb_notifications
  ]
}

# ==========================================
# 📤 OUTPUTS
# ==========================================
output "sqs_cloudtrail_queue_url" {
  value       = aws_sqs_queue.cloudtrail_notifications.url
  description = "CloudTrail SQS Queue URL"
}

output "sqs_cloudtrail_queue_arn" {
  value       = aws_sqs_queue.cloudtrail_notifications.arn
  description = "CloudTrail SQS Queue ARN"
}

output "sqs_vpcflow_queue_url" {
  value       = aws_sqs_queue.vpcflow_notifications.url
  description = "VPC Flow Logs SQS Queue URL"
}

output "sqs_vpcflow_queue_arn" {
  value       = aws_sqs_queue.vpcflow_notifications.arn
  description = "VPC Flow Logs SQS Queue ARN"
}

output "sqs_alb_queue_url" {
  value       = aws_sqs_queue.alb_notifications.url
  description = "ALB SQS Queue URL"
}

output "sqs_alb_queue_arn" {
  value       = aws_sqs_queue.alb_notifications.arn
  description = "ALB SQS Queue ARN"
}
