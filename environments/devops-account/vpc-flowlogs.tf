# Cấu hình VPC Flow Logs đẩy thẳng logs sang S3 Bucket tập trung ở tài khoản Monitor
# TẠM TẮT ĐỂ FIX LỖI: Bucket centralized-logs chưa được tạo ở tài khoản Monitor
# resource "aws_flow_log" "devops_vpc_flowlog" {
#   log_destination      = "arn:aws:s3:::${var.project}-centralized-logs-${var.monitor_account_id}/vpc-flowlogs/"
#   log_destination_type = "s3"
#   traffic_type         = "ALL"
#   vpc_id               = aws_vpc.main.id
# 
#   tags = {
#     Name        = "devops-vpc-flowlog"
#     Environment = var.env
#     ManagedBy   = "Terraform"
#   }
# }
