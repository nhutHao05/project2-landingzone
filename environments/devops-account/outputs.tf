# ── Networking ───────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID của VPC — dùng cho debugging và khi tạo thêm resource sau"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs của public subnets — ALB đang đứng ở đây"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs của private subnets — Ansible cần để biết EC2 nằm ở đâu"
  value       = aws_subnet.private[*].id
}

# ── Load Balancer ─────────────────────────────────────────────────────
output "alb_dns_name" {
  description = "DNS của ALB — paste vào browser để test app sau khi deploy"
  value       = aws_lb.alb.dns_name
}

# output "alb_arn" {
#   description = "ARN của ALB — cần nếu sau này gắn thêm WAF hoặc listener"
#   value       = aws_lb.alb.arn
# }

# ── Database ──────────────────────────────────────────────────────────
# output "db_endpoint" {
#   description = "Endpoint RDS — app dùng cái này để kết nối database"
#   value       = aws_db_instance.main.endpoint
# }

# output "db_name" {
#   description = "Tên database instance trên AWS"
#   value       = aws_db_instance.main.identifier
# }

# Password sensitive: không hiện ra khi terraform output bình thường
# Muốn xem: terraform output -raw db_password
# output "db_password" {
#   description = "Password RDS được generate tự động — chỉ xem khi cần debug"
#   value       = random_password.db_password.result
#   sensitive   = true
# }

# ── Compute ───────────────────────────────────────────────────────────
output "ec2_instance_ids" {
  description = "IDs của 2 EC2 app node — dùng cho SSM session và debug"
  value       = { for k, v in aws_autoscaling_group.app : k => v.id }
}
output "asg_names" {
  description = "Names of all ASGs"
  value = {
    for k, v in aws_autoscaling_group.app : k => v.name
  }
}