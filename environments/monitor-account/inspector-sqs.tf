# ==========================================
# Amazon Inspector Findings -> SQS (Phase 1)
# ==========================================
# Dedicated queue for Inspector findings forwarded from the DevOps account.
# This keeps existing CloudTrail/VPC/ALB SQS queues untouched.

resource "aws_sqs_queue" "inspector_findings" {
  name                       = "${var.project_name}-inspector-findings"
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 300

  tags = {
    Name        = "${var.project_name}-inspector-findings"
    Description = "Amazon Inspector findings forwarded from DevOps EventBridge"
  }
}

resource "aws_sqs_queue_policy" "inspector_findings" {
  queue_url = aws_sqs_queue.inspector_findings.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDevOpsEventBridgeToSendInspectorFindings"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.inspector_findings.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = "arn:aws:events:${var.aws_region}:${var.devops_account_id}:rule/${var.project_name}-inspector-findings-to-monitor"
          }
          StringEquals = {
            "aws:SourceAccount" = var.devops_account_id
          }
        }
      },
      {
        Sid    = "AllowMasterEventBridgeToSendInspectorFindings"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.inspector_findings.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = "arn:aws:events:${var.aws_region}:${var.master_account_id}:rule/${var.project_name}-inspector-findings-to-monitor-master"
          }
          StringEquals = {
            "aws:SourceAccount" = var.master_account_id
          }
        }
      }
    ]
  })
}

output "sqs_inspector_queue_url" {
  value       = aws_sqs_queue.inspector_findings.url
  description = "Amazon Inspector Findings SQS Queue URL"
}

output "sqs_inspector_queue_arn" {
  value       = aws_sqs_queue.inspector_findings.arn
  description = "Amazon Inspector Findings SQS Queue ARN"
}
