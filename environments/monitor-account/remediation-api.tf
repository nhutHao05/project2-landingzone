# ==========================================
# Web Portal Remediation API (Phase 6 — Cognito + Step Functions)
# ==========================================

locals {
  effective_devops_remediation_role_arn = var.devops_remediation_role_arn != "" ? var.devops_remediation_role_arn : "arn:aws:iam::${var.devops_account_id}:role/${var.devops_project}-${var.devops_env}-${var.devops_region_short}-monitor-remediation-role"
}

# ---------- Legacy Remediation Lambda (giữ lại cho backward compat) ----------
data "archive_file" "remediation_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/remediation"
  output_path = "${path.module}/lambda/remediation_payload.zip"
}

resource "aws_iam_role" "remediation_lambda" {
  name = "${var.project_name}-remediation-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "remediation_lambda" {
  name = "${var.project_name}-remediation-lambda-policy"
  role = aws_iam_role.remediation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowLambdaLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid    = "AllowIncidentTableAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.incidents.arn
      },
      {
        Sid      = "AllowDevOpsRemediationAssumeRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.effective_devops_remediation_role_arn
      }
    ]
  })
}

resource "aws_lambda_function" "remediation" {
  filename         = data.archive_file.remediation_lambda_zip.output_path
  source_code_hash = data.archive_file.remediation_lambda_zip.output_base64sha256
  function_name    = "${var.project_name}-remediation"
  role             = aws_iam_role.remediation_lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      DYNAMODB_TABLE              = aws_dynamodb_table.incidents.name
      DEVOPS_REMEDIATION_ROLE_ARN = local.effective_devops_remediation_role_arn
    }
  }

  depends_on = [
    aws_iam_role_policy.remediation_lambda
  ]

  tags = {
    Name = "${var.project_name}-remediation-lambda"
  }
}

# ==========================================
# API Gateway — REST API with Cognito Authorizer
# ==========================================

resource "aws_api_gateway_rest_api" "remediation" {
  name        = "${var.project_name}-remediation-api"
  description = "Monitor Account API Gateway for SOAR Web Portal (Cognito-protected)"
}

# ---------- Cognito Authorizer ----------
resource "aws_api_gateway_authorizer" "cognito" {
  name            = "${var.project_name}-cognito-authorizer"
  rest_api_id     = aws_api_gateway_rest_api.remediation.id
  type            = "COGNITO_USER_POOLS"
  identity_source = "method.request.header.Authorization"

  provider_arns = [
    aws_cognito_user_pool.portal.arn
  ]
}

# ==========================================
# Resource: /remediate (POST + OPTIONS)
# ==========================================
resource "aws_api_gateway_resource" "remediate" {
  rest_api_id = aws_api_gateway_rest_api.remediation.id
  parent_id   = aws_api_gateway_rest_api.remediation.root_resource_id
  path_part   = "remediate"
}

resource "aws_api_gateway_method" "remediate_options" {
  rest_api_id   = aws_api_gateway_rest_api.remediation.id
  resource_id   = aws_api_gateway_resource.remediate.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "remediate_post" {
  rest_api_id   = aws_api_gateway_rest_api.remediation.id
  resource_id   = aws_api_gateway_resource.remediate.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "remediate_options" {
  rest_api_id             = aws_api_gateway_rest_api.remediation.id
  resource_id             = aws_api_gateway_resource.remediate.id
  http_method             = aws_api_gateway_method.remediate_options.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation.invoke_arn
}

resource "aws_api_gateway_integration" "remediate_post" {
  rest_api_id             = aws_api_gateway_rest_api.remediation.id
  resource_id             = aws_api_gateway_resource.remediate.id
  http_method             = aws_api_gateway_method.remediate_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation.invoke_arn
}

# ==========================================
# Resource: /incidents (GET + OPTIONS)
# ==========================================
resource "aws_api_gateway_resource" "incidents" {
  rest_api_id = aws_api_gateway_rest_api.remediation.id
  parent_id   = aws_api_gateway_rest_api.remediation.root_resource_id
  path_part   = "incidents"
}

resource "aws_api_gateway_method" "incidents_options" {
  rest_api_id   = aws_api_gateway_rest_api.remediation.id
  resource_id   = aws_api_gateway_resource.incidents.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "incidents_get" {
  rest_api_id   = aws_api_gateway_rest_api.remediation.id
  resource_id   = aws_api_gateway_resource.incidents.id
  http_method   = "GET"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "incidents_options" {
  rest_api_id             = aws_api_gateway_rest_api.remediation.id
  resource_id             = aws_api_gateway_resource.incidents.id
  http_method             = aws_api_gateway_method.incidents_options.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation.invoke_arn
}

resource "aws_api_gateway_integration" "incidents_get" {
  rest_api_id             = aws_api_gateway_rest_api.remediation.id
  resource_id             = aws_api_gateway_resource.incidents.id
  http_method             = aws_api_gateway_method.incidents_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation.invoke_arn
}

# ==========================================
# Resource: /callback (POST + OPTIONS) — Step Functions TaskToken
# ==========================================
resource "aws_api_gateway_resource" "callback" {
  rest_api_id = aws_api_gateway_rest_api.remediation.id
  parent_id   = aws_api_gateway_rest_api.remediation.root_resource_id
  path_part   = "callback"
}

resource "aws_api_gateway_method" "callback_options" {
  rest_api_id   = aws_api_gateway_rest_api.remediation.id
  resource_id   = aws_api_gateway_resource.callback.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "callback_post" {
  rest_api_id   = aws_api_gateway_rest_api.remediation.id
  resource_id   = aws_api_gateway_resource.callback.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito.id
}

resource "aws_api_gateway_integration" "callback_options" {
  rest_api_id             = aws_api_gateway_rest_api.remediation.id
  resource_id             = aws_api_gateway_resource.callback.id
  http_method             = aws_api_gateway_method.callback_options.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation_callback.invoke_arn
}

resource "aws_api_gateway_integration" "callback_post" {
  rest_api_id             = aws_api_gateway_rest_api.remediation.id
  resource_id             = aws_api_gateway_resource.callback.id
  http_method             = aws_api_gateway_method.callback_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation_callback.invoke_arn
}

# ==========================================
# Lambda Permissions for API Gateway
# ==========================================
resource "aws_lambda_permission" "remediation_apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.remediation.execution_arn}/*/*"
}

resource "aws_lambda_permission" "callback_apigw" {
  statement_id  = "AllowCallbackFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation_callback.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.remediation.execution_arn}/*/*"
}

# ==========================================
# Deployment & Stage
# ==========================================
resource "aws_api_gateway_deployment" "remediation" {
  depends_on = [
    aws_api_gateway_integration.remediate_options,
    aws_api_gateway_integration.remediate_post,
    aws_api_gateway_integration.incidents_options,
    aws_api_gateway_integration.incidents_get,
    aws_api_gateway_integration.callback_options,
    aws_api_gateway_integration.callback_post
  ]

  rest_api_id = aws_api_gateway_rest_api.remediation.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.remediate.id,
      aws_api_gateway_resource.incidents.id,
      aws_api_gateway_resource.callback.id,
      aws_api_gateway_method.remediate_options.id,
      aws_api_gateway_method.remediate_post.id,
      aws_api_gateway_method.incidents_options.id,
      aws_api_gateway_method.incidents_get.id,
      aws_api_gateway_method.callback_options.id,
      aws_api_gateway_method.callback_post.id,
      aws_api_gateway_integration.remediate_options.id,
      aws_api_gateway_integration.remediate_post.id,
      aws_api_gateway_integration.incidents_options.id,
      aws_api_gateway_integration.incidents_get.id,
      aws_api_gateway_integration.callback_options.id,
      aws_api_gateway_integration.callback_post.id,
      aws_api_gateway_authorizer.cognito.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "remediation" {
  deployment_id = aws_api_gateway_deployment.remediation.id
  rest_api_id   = aws_api_gateway_rest_api.remediation.id
  stage_name    = "prod"
}

# ==========================================
# Config JSON cho Web Portal (auto-generated by Terraform)
# ==========================================
resource "local_file" "web_portal_config" {
  content = jsonencode({
    API_GATEWAY_URL   = "${aws_api_gateway_stage.remediation.invoke_url}/remediate"
    INCIDENTS_API_URL = "${aws_api_gateway_stage.remediation.invoke_url}/incidents"
    CALLBACK_API_URL  = "${aws_api_gateway_stage.remediation.invoke_url}/callback"
    COGNITO_DOMAIN    = "https://${var.cognito_domain_prefix}.auth.${var.aws_region}.amazoncognito.com"
    COGNITO_CLIENT_ID = aws_cognito_user_pool_client.portal_spa.id
    COGNITO_REDIRECT_URI = var.cognito_callback_urls[0]
    COGNITO_LOGOUT_URI   = var.cognito_logout_urls[0]
  })
  filename = "${path.module}/../../web-portal/config.json"
}

# ==========================================
# Outputs
# ==========================================
output "remediation_api_url" {
  value       = "${aws_api_gateway_stage.remediation.invoke_url}/remediate"
  description = "Exact URL used by Web Portal approve/reject calls"
}

output "incidents_api_url" {
  value       = "${aws_api_gateway_stage.remediation.invoke_url}/incidents"
  description = "Exact URL used by Web Portal incident list calls"
}

output "callback_api_url" {
  value       = "${aws_api_gateway_stage.remediation.invoke_url}/callback"
  description = "Exact URL used by Web Portal Step Functions callback calls"
}

output "remediation_lambda_role_arn" {
  value       = aws_iam_role.remediation_lambda.arn
  description = "Role ARN trusted by DevOps cross-account remediation role"
}
