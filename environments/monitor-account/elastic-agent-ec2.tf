# ==========================================
# 🖥️ EC2 — Elastic Agent Host
# ==========================================
# Con EC2 này sẽ:
#   1. Poll SQS queue để biết có file CloudTrail mới
#   2. Download file .json.gz từ S3
#   3. Parse và đẩy logs vào Elasticsearch (elastic.hungcx.cloud)
#
# Chỉ deploy khi var.enable_elastic_agent_ec2 = true
# ==========================================

# ---- Data Sources ----
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Lấy Default VPC của Monitor Account (không cần tạo VPC riêng cho agent nhỏ này)
data "aws_vpc" "default" {
  count   = (var.enable_elastic_agent_ec2 || var.enable_web_portal_ec2) ? 1 : 0
  default = true
}

data "aws_subnets" "default" {
  count = (var.enable_elastic_agent_ec2 || var.enable_web_portal_ec2) ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default[0].id]
  }
}

# ==========================================
# 🔐 SECURITY GROUP — Chỉ cho phép outbound
# ==========================================
resource "aws_security_group" "elastic_agent" {
  count       = var.enable_elastic_agent_ec2 ? 1 : 0
  name        = "${var.project_name}-elastic-agent-sg"
  description = "Security group for Elastic Agent EC2 - outbound only"
  vpc_id      = data.aws_vpc.default[0].id

  # Outbound: cho phép kết nối ra ngoài (đến elastic.hungcx.cloud và AWS APIs)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  # Không có inbound rule → không ai kết nối được vào EC2 này
  # Quản lý qua SSM (không cần SSH, không cần public IP)

  tags = {
    Name = "${var.project_name}-elastic-agent-sg"
  }
}

# ==========================================
# 🔑 IAM ROLE — Cho phép SSM quản lý EC2
# ==========================================
resource "aws_iam_role" "elastic_agent_ec2" {
  count = var.enable_elastic_agent_ec2 ? 1 : 0
  name  = "${var.project_name}-elastic-agent-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach SSM policy để quản lý EC2 qua AWS Console (không cần key pair hay bastion)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  count      = var.enable_elastic_agent_ec2 ? 1 : 0
  role       = aws_iam_role.elastic_agent_ec2[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "elastic_agent_ec2_policy" {
  count = var.enable_elastic_agent_ec2 ? 1 : 0
  name  = "${var.project_name}-elastic-agent-ec2-policy"
  role  = aws_iam_role.elastic_agent_ec2[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowS3ReadLogs"
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
        Sid    = "AllowSQSProcessNotifications"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:ChangeMessageVisibility"
        ]
        Resource = "arn:aws:sqs:${var.aws_region}:${var.monitor_account_id}:${var.project_name}-*"
      },
      {
        Sid    = "AllowAssumeRole"
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowAWSIntegrationRead"
        Effect = "Allow"
        Action = [
          "ec2:DescribeRegions",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs",
          "ec2:DescribeTransitGateways",
          "ec2:DescribeVolumes",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "rds:DescribeDBInstances",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
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

resource "aws_iam_instance_profile" "elastic_agent_ec2" {
  count = var.enable_elastic_agent_ec2 ? 1 : 0
  name  = "${var.project_name}-elastic-agent-ec2-profile"
  role  = aws_iam_role.elastic_agent_ec2[0].name
}

# ==========================================
# 🖥️ EC2 INSTANCE
# ==========================================
resource "aws_instance" "elastic_agent" {
  count = var.enable_elastic_agent_ec2 ? 1 : 0

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.small"
  subnet_id              = data.aws_subnets.default[0].ids[0]
  vpc_security_group_ids = [aws_security_group.elastic_agent[0].id]
  iam_instance_profile   = aws_iam_instance_profile.elastic_agent_ec2[0].name

  # Cần public IP để EC2 có thể:
  # 1. Download Elastic Agent từ artifacts.elastic.co
  # 2. Kết nối Fleet Server tại elastic.hungcx.cloud:8220
  associate_public_ip_address = true

  # ----------------------------------------
  # User Data: Cài đặt Elastic Agent khi EC2 khởi động lần đầu
  # Điền Fleet URL và Enrollment Token sau khi lấy từ Kibana
  # ----------------------------------------
  user_data = base64encode(templatefile("${path.module}/scripts/install-elastic-agent.sh.tpl", {
    fleet_url        = var.elastic_fleet_url
    enrollment_token = var.elastic_enrollment_token
  }))

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-elastic-agent"
  }
}

# ==========================================
# 📤 OUTPUTS
# ==========================================
output "elastic_agent_instance_id" {
  value       = var.enable_elastic_agent_ec2 ? aws_instance.elastic_agent[0].id : null
  description = "EC2 Instance ID cua Elastic Agent — Dung de SSM vao kiem tra logs"
}
