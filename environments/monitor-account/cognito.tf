# ==========================================
# AWS Cognito — Web Portal SSO (Phase 6)
# ==========================================
# Cognito User Pool cung cấp SSO thật cho Web Portal,
# thay thế mock login hiện tại.
# Sử dụng PKCE (Proof Key for Code Exchange) cho SPA static HTML.

# ---------- User Pool ----------
resource "aws_cognito_user_pool" "portal" {
  name = "${var.project_name}-portal-users"

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  # Username attributes — đăng nhập bằng email
  username_attributes = ["email"]

  auto_verified_attributes = ["email"]

  # Schema attributes
  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 5
      max_length = 128
    }
  }

  schema {
    name                = "name"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 128
    }
  }

  # MFA — optional cho lab, bật lên nếu muốn
  mfa_configuration = "OFF"

  # Account recovery via email
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # Admin create user — tắt self-service sign-up (chỉ admin tạo user)
  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_message = "Your SOAR Portal account has been created. Username: {username}, Temporary password: {####}"
      email_subject = "SOAR Portal — Account Created"
      sms_message   = "Your SOAR Portal username is {username} and temporary password is {####}"
    }
  }

  tags = {
    Name = "${var.project_name}-portal-users"
  }
}

# ---------- User Pool Domain (Hosted UI) ----------
resource "aws_cognito_user_pool_domain" "portal" {
  domain       = var.cognito_domain_prefix
  user_pool_id = aws_cognito_user_pool.portal.id
}

# ---------- App Client (SPA — PKCE, no client secret) ----------
resource "aws_cognito_user_pool_client" "portal_spa" {
  name         = "${var.project_name}-portal-spa"
  user_pool_id = aws_cognito_user_pool.portal.id

  # PKCE — no client secret for SPA
  generate_secret = false

  # OAuth2 flows
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  # Callback URLs — sẽ update sau khi biết public IP/domain của EC2
  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  supported_identity_providers = ["COGNITO"]

  # Token validity
  access_token_validity  = 1  # 1 hour
  id_token_validity      = 1  # 1 hour
  refresh_token_validity = 30 # 30 days

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }

  # Prevent user existence errors (security best practice)
  prevent_user_existence_errors = "ENABLED"
}

# ---------- User Pool Groups ----------
resource "aws_cognito_user_group" "admin" {
  name         = "Admin"
  user_pool_id = aws_cognito_user_pool.portal.id
  description  = "Full access — can approve/reject remediation actions"
}

resource "aws_cognito_user_group" "analyst" {
  name         = "Analyst"
  user_pool_id = aws_cognito_user_pool.portal.id
  description  = "Can view incidents and approve/reject remediation actions"
}

resource "aws_cognito_user_group" "readonly" {
  name         = "ReadOnly"
  user_pool_id = aws_cognito_user_pool.portal.id
  description  = "View-only access to incident dashboard"
}

# ---------- Outputs ----------
output "cognito_user_pool_id" {
  value       = aws_cognito_user_pool.portal.id
  description = "Cognito User Pool ID cho Web Portal"
}

output "cognito_app_client_id" {
  value       = aws_cognito_user_pool_client.portal_spa.id
  description = "Cognito App Client ID (SPA, PKCE)"
}

output "cognito_domain" {
  value       = "https://${var.cognito_domain_prefix}.auth.${var.aws_region}.amazoncognito.com"
  description = "Cognito Hosted UI domain URL"
}

output "cognito_hosted_ui_login_url" {
  value       = "https://${var.cognito_domain_prefix}.auth.${var.aws_region}.amazoncognito.com/login?client_id=${aws_cognito_user_pool_client.portal_spa.id}&response_type=code&scope=email+openid+profile&redirect_uri=${urlencode(var.cognito_callback_urls[0])}"
  description = "Full Cognito Hosted UI login URL (dùng cho Web Portal redirect)"
}
