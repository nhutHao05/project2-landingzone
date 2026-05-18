locals {
  centralized_logs_bucket_name = "${var.project_name}-centralized-logs-${var.monitor_account_id}"
  org_trail_arn                = "arn:aws:cloudtrail:${var.aws_region}:${var.master_account_id}:trail/${var.org_trail_name}"
}

resource "aws_s3_bucket" "centralized_logs" {
  bucket        = local.centralized_logs_bucket_name
  force_destroy = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "centralized_logs" {
  bucket = aws_s3_bucket.centralized_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "centralized_logs" {
  bucket = aws_s3_bucket.centralized_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "centralized_logs" {
  bucket = aws_s3_bucket.centralized_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "centralized_logs" {
  bucket = aws_s3_bucket.centralized_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailGetAcl"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.centralized_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.org_trail_arn
          }
        }
      },
      {
        Sid    = "AllowOrganizationCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.centralized_logs.arn}/AWSLogs/${var.organization_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.org_trail_arn
            "s3:x-amz-acl"  = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowVpcFlowLogsAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.centralized_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.devops_account_id
          }
        }
      },
      {
        Sid    = "AllowVpcFlowLogsWrite"
        Effect = "Allow"
        Principal = {
          Service = "delivery.logs.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.centralized_logs.arn}/vpc-flowlogs/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.devops_account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AllowAlbAccessLogsWrite"
        Effect = "Allow"
        Principal = {
          Service = "logdelivery.elasticloadbalancing.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.centralized_logs.arn}/alb-logs/*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = var.devops_account_id
            "s3:x-amz-acl"      = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

output "centralized_logs_bucket_name" {
  value       = aws_s3_bucket.centralized_logs.id
  description = "Ten cua Centralized S3 Log Bucket"
}

output "centralized_logs_bucket_arn" {
  value       = aws_s3_bucket.centralized_logs.arn
  description = "ARN cua Centralized S3 Log Bucket"
}
