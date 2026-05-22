# ==========================================
# DynamoDB — Incident Store (Phase 3 & 5)
# ==========================================
# Bảng này lưu trữ kết quả phân tích của AI Engine.
# Web Portal (Phase 5) sẽ query dữ liệu từ đây để hiển thị cho Analyst.

resource "aws_dynamodb_table" "incidents" {
  name         = "${var.project_name}-incidents"
  billing_mode = "PAY_PER_REQUEST" # Tiết kiệm cho môi trường lab/low traffic
  hash_key     = "incident_id"

  attribute {
    name = "incident_id"
    type = "S"
  }

  attribute {
    name = "severity"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  # Global Secondary Index để lấy danh sách incident theo thời gian
  global_secondary_index {
    name            = "severity-timestamp-index"
    hash_key        = "severity"
    range_key       = "timestamp"
    projection_type = "ALL"
  }

  # TTL để tự động xóa các log quá cũ (90 ngày cấu hình trong Lambda)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "${var.project_name}-incidents"
  }
}

# Output tên bảng
output "dynamodb_incident_table" {
  value       = aws_dynamodb_table.incidents.name
  description = "DynamoDB table luu tru AI security incidents"
}
