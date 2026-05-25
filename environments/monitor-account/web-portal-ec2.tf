# ==========================================
# EC2 — Static Web Portal Host
# ==========================================

locals {
  web_portal_ansible_bucket_name = "${var.project_name}-monitor-ansible-ssm-temp"
}

resource "aws_s3_bucket" "web_portal_ansible_ssm_temp" {
  count  = var.enable_web_portal_ec2 ? 1 : 0
  bucket = local.web_portal_ansible_bucket_name
}

resource "aws_s3_bucket_public_access_block" "web_portal_ansible_ssm_temp" {
  count  = var.enable_web_portal_ec2 ? 1 : 0
  bucket = aws_s3_bucket.web_portal_ansible_ssm_temp[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "web_portal_ansible_ssm_temp" {
  count  = var.enable_web_portal_ec2 ? 1 : 0
  bucket = aws_s3_bucket.web_portal_ansible_ssm_temp[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowManagementAccountAnsibleSsmTransport"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${var.master_account_id}:root"
      }
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ]
      Resource = [
        aws_s3_bucket.web_portal_ansible_ssm_temp[0].arn,
        "${aws_s3_bucket.web_portal_ansible_ssm_temp[0].arn}/*"
      ]
    }]
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "web_portal_ansible_ssm_temp" {
  count  = var.enable_web_portal_ec2 ? 1 : 0
  bucket = aws_s3_bucket.web_portal_ansible_ssm_temp[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "web_portal_ansible_ssm_temp" {
  count  = var.enable_web_portal_ec2 ? 1 : 0
  bucket = aws_s3_bucket.web_portal_ansible_ssm_temp[0].id

  rule {
    id     = "expire-ansible-ssm-temp-objects"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 7
    }
  }
}

resource "aws_security_group" "web_portal" {
  count       = var.enable_web_portal_ec2 ? 1 : 0
  name        = "${var.project_name}-web-portal-sg"
  description = "Security group for static Web Portal host - SSM access only"
  vpc_id      = data.aws_vpc.default[0].id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow outbound traffic for SSM, Docker package install, and API calls"
  }

  tags = {
    Name = "${var.project_name}-web-portal-sg"
  }
}

resource "aws_iam_role" "web_portal_ec2" {
  count = var.enable_web_portal_ec2 ? 1 : 0
  name  = "${var.project_name}-web-portal-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "web_portal_ssm_core" {
  count      = var.enable_web_portal_ec2 ? 1 : 0
  role       = aws_iam_role.web_portal_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "web_portal_ansible_ssm_bucket" {
  count = var.enable_web_portal_ec2 ? 1 : 0
  name  = "${var.project_name}-web-portal-ansible-ssm-bucket"
  role  = aws_iam_role.web_portal_ec2[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ]
      Resource = [
        aws_s3_bucket.web_portal_ansible_ssm_temp[0].arn,
        "${aws_s3_bucket.web_portal_ansible_ssm_temp[0].arn}/*"
      ]
    }]
  })
}

resource "aws_iam_instance_profile" "web_portal_ec2" {
  count = var.enable_web_portal_ec2 ? 1 : 0
  name  = "${var.project_name}-web-portal-ec2-profile"
  role  = aws_iam_role.web_portal_ec2[0].name
}

resource "aws_instance" "web_portal" {
  count = var.enable_web_portal_ec2 ? 1 : 0

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.web_portal_instance_type
  subnet_id                   = data.aws_subnets.default[0].ids[0]
  vpc_security_group_ids      = [aws_security_group.web_portal[0].id]
  iam_instance_profile        = aws_iam_instance_profile.web_portal_ec2[0].name
  associate_public_ip_address = true

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y docker
    systemctl enable --now docker
    usermod -aG docker ec2-user
  EOF
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-web-portal"
    Role = "portal"
  }
}

output "web_portal_instance_id" {
  value       = var.enable_web_portal_ec2 ? aws_instance.web_portal[0].id : null
  description = "EC2 Instance ID cua static Web Portal trong Monitor Account"
}

output "web_portal_ansible_ssm_bucket" {
  value       = var.enable_web_portal_ec2 ? aws_s3_bucket.web_portal_ansible_ssm_temp[0].bucket : null
  description = "S3 bucket dung cho Ansible SSM khi deploy static Web Portal"
}
