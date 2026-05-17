# 1. Tạo S3 Bucket nhận logs tập trung
# Thêm đuôi account_id để đảm bảo tên bucket là DUY NHẤT trên toàn thế giới
resource "aws_s3_bucket" "centralized_logs" {
  bucket        = "${var.project_name}-centralized-logs-${var.monitor_account_id}"
  force_destroy = true
}

# 2. Ngăn chặn triệt để mọi quyền truy cập Public vào Log Bucket
resource "aws_s3_bucket_public_access_block" "block_public" {
  bucket = aws_s3_bucket.centralized_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 3. Gắn S3 Bucket Policy cấp quyền ghi chéo tài khoản cho CloudTrail và VPC Flow logs
resource "aws_s3_bucket_policy" "log_bucket_policy" {
  bucket = aws_s3_bucket.centralized_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Quyền A: Cho phép dịch vụ CloudTrail kiểm tra thuộc tính ACL của Bucket
      {
        Sid    = "AllowCloudTrailGetAcl"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = "${aws_s3_bucket.centralized_logs.arn}"
      },
      # Quyền B: Cho phép CloudTrail đẩy Logs từ toàn bộ các tài khoản của Org vào thư mục AWSLogs/
      {
        Sid    = "AllowCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.centralized_logs.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      # Quyền C: Cho phép dịch vụ Log Delivery của AWS (tài khoản DevOps) được phép đẩy VPC Flow logs và ALB Access logs
      {
        Sid    = "AllowDevOpsLogs"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = ["s3:PutObject", "s3:GetBucketAcl"]
        Resource = [
          "${aws_s3_bucket.centralized_logs.arn}",
          "${aws_s3_bucket.centralized_logs.arn}/vpc-flowlogs/*",
          "${aws_s3_bucket.centralized_logs.arn}/alb-logs/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = "${var.devops_account_id}"
          }
        }
      }
    ]
  })
}

# Output tên Bucket để cấu hình ở các bước sau dễ dàng
output "centralized_logs_bucket_name" {
  value       = aws_s3_bucket.centralized_logs.id
  description = "Ten cua Centralized S3 Log Bucket"
}

output "centralized_logs_bucket_arn" {
  value       = aws_s3_bucket.centralized_logs.arn
  description = "ARN cua Centralized S3 Log Bucket"
}
