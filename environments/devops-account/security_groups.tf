# ── ALB SG — nhận HTTP/HTTPS từ internet ────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-sg-alb"
  description = "Allow HTTP/HTTPS inbound from internet"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-sg-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = local.ports.http
  to_port           = local.ports.http
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = local.ports.https
  to_port           = local.ports.https
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_egress" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ── LAYER 1: WEB APP SG (Nhận từ ALB) ───────────────────────────────────
resource "aws_security_group" "web" {
  name        = "${local.name_prefix}-sg-web"
  description = "Layer 1: External Facing Web App"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-sg-layer-1" }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = aws_security_group.web.id
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
}

# ── LAYER 2: LOG ANALYSIS SG (CHỈ nhận từ LAYER 1) ──────────────────────
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-sg-app"
  description = "Layer 2: Internal Log Analysis Logic"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-sg-layer-2" }
}

# ── SSM ENDPOINTS SG (Cổng dùng chung cho tất cả các máy kết nối SSM) ──
resource "aws_security_group" "ssm_endpoints" {
  name        = "${local.name_prefix}-sg-ssm-endpoints"
  description = "Access to SSM Endpoints"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-sg-ssm-endpoints" }
}

resource "aws_vpc_security_group_ingress_rule" "ssm_endpoints_https" {
  security_group_id = aws_security_group.ssm_endpoints.id
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ── EGRESS RULES (Cho phép máy chủ đi ra ngoài) ─────────────────────────
resource "aws_vpc_security_group_egress_rule" "web_egress" {
  security_group_id = aws_security_group.web.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "app_egress" {
  security_group_id = aws_security_group.app.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ── DB SG — chỉ nhận từ App SG ──────────────────────────────────────
resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-sg-db"
  description = "Allow inbound from App SG only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-sg-db"
  }
}

resource "aws_vpc_security_group_ingress_rule" "db_from_web_mysql" {
  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_security_group.web.id
  from_port                    = local.ports.db
  to_port                      = local.ports.db
  ip_protocol                  = "tcp"
}

# DB không có egress — isolated by design, deny all outbound
