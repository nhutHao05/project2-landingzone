resource "aws_iam_role" "ec2_role" {
  name = "${local.name_prefix}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

}

resource "aws_iam_role_policy_attachment" "ec2_role_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "${local.name_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_iam_policy" "ai_log_analyzer_policy" {
  name        = "${local.name_prefix}-ai-log-analyzer-policy"
  description = "Policy for AI Log Analyzer to access CloudWatch and Bedrock"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ai_log_analyzer_policy_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ai_log_analyzer_policy.arn
}


# Cấp quyền cho EC2 truy cập vào S3 Bucket trung chuyển của Ansible
resource "aws_iam_policy" "ansible_s3_policy" {
  name        = "${local.name_prefix}-ansible-s3-policy"
  description = "Allow EC2 to access Ansible SSM temp bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.ansible_ssm_temp.arn,
          "${aws_s3_bucket.ansible_ssm_temp.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ansible_s3_attachment" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ansible_s3_policy.arn
}

# ==========================================
# 🔐 CROSS-ACCOUNT ROLE — Cho phép Monitor Account Elastic Agent đọc CloudWatch logs
# ==========================================
resource "aws_iam_role" "elastic_cloudwatch_cross_account_role" {
  name        = "${local.name_prefix}-elastic-cloudwatch-role"
  description = "Cross-account IAM Role for Monitor Elastic Agent to read CloudWatch logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = [
            "arn:aws:iam::${var.monitor_account_id}:root",
            "arn:aws:iam::${var.monitor_account_id}:role/${var.project}-elastic-agent-ec2-role"
          ]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "elastic_cloudwatch_policy" {
  name        = "${local.name_prefix}-elastic-cloudwatch-policy"
  description = "Allows reading CloudWatch Logs in DevOps account"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents",
          "logs:GetLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "elastic_cloudwatch_attach" {
  role       = aws_iam_role.elastic_cloudwatch_cross_account_role.name
  policy_arn = aws_iam_policy.elastic_cloudwatch_policy.arn
}

# ==========================================
# CROSS-ACCOUNT ROLE — Cho phép Monitor remediation Lambda thao tác tài nguyên DevOps
# ==========================================
resource "aws_iam_role" "monitor_remediation_cross_account_role" {
  name        = "${local.name_prefix}-monitor-remediation-role"
  description = "Cross-account role assumed by Monitor remediation Lambda for approved SOAR actions"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.monitor_account_id}:role/${var.monitor_remediation_lambda_role_name}"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "monitor_remediation_cross_account_policy" {
  name        = "${local.name_prefix}-monitor-remediation-policy"
  description = "Allows Monitor remediation Lambda to execute approved actions in DevOps account"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:CreateSecurityGroup",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:ModifyInstanceAttribute"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "wafv2:GetIPSet",
          "wafv2:UpdateIPSet"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "monitor_remediation_cross_account_attach" {
  role       = aws_iam_role.monitor_remediation_cross_account_role.name
  policy_arn = aws_iam_policy.monitor_remediation_cross_account_policy.arn
}

