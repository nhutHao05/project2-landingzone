# Custom Parameter Group để bật Slow Query Log
resource "aws_db_parameter_group" "mysql" {
  name        = "${local.name_prefix}-mysql-params"
  family      = "mysql8.0"
  description = "Custom parameter group with slow query logging enabled"

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "1"
  }

  parameter {
    name         = "log_output"
    value        = "FILE"
    apply_method = "pending-reboot"
  }

  tags = {
    Name        = "${local.name_prefix}-mysql-params"
    Environment = var.env
    ManagedBy   = "Terraform"
  }
}

resource "aws_db_subnet_group" "db" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.db[*].id

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

resource "random_password" "db_password" {
  length           = 16
  special          = true
  override_special = "!#$%"
}

resource "aws_db_instance" "main" {
  identifier     = "${local.name_prefix}-db"
  instance_class = "db.t3.micro"
  engine         = "mysql"
  engine_version = "8.0"
  db_name        = var.app_db_name
  username       = var.db_username
  password       = random_password.db_password.result

  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.db.name
  vpc_security_group_ids = [aws_security_group.db.id]

  allocated_storage = 20
  storage_type      = "gp2"
  enabled_cloudwatch_logs_exports = ["error", "slowquery"]
  parameter_group_name            = aws_db_parameter_group.mysql.name

  skip_final_snapshot = true
  tags = {
    Name        = "${local.name_prefix}-db"
    Environment = var.env
  }
}

output "db_endpoint" {
  value = aws_db_instance.main.address
}

output "db_password" {
  value     = random_password.db_password.result
  sensitive = true
}

# Lưu thông tin bảo mật vào SSM
resource "aws_ssm_parameter" "db_host" {
  name  = "${var.app_ssm_prefix}/${var.env}/db/host"
  type  = "String"
  value = aws_db_instance.main.address
}

resource "aws_ssm_parameter" "db_user" {
  name  = "${var.app_ssm_prefix}/${var.env}/db/user"
  type  = "String"
  value = var.db_username
}

resource "aws_ssm_parameter" "db_pass" {
  name  = "${var.app_ssm_prefix}/${var.env}/db/password"
  type  = "SecureString"
  value = random_password.db_password.result
}

resource "aws_ssm_parameter" "db_name" {
  name  = "${var.app_ssm_prefix}/${var.env}/db/name"
  type  = "String"
  value = var.app_db_name
}
