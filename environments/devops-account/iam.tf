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

