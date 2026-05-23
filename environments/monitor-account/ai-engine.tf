# ==========================================
# Lambda Function — AI Engine
# ==========================================

# 1. IAM Role cho Lambda
resource "aws_iam_role" "ai_engine_lambda" {
  name = "${var.project_name}-ai-engine-role"

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

# 2. IAM Policy cho Lambda (CloudWatch, DynamoDB, Bedrock)
resource "aws_iam_policy" "ai_engine_policy" {
  name        = "${var.project_name}-ai-engine-policy"
  description = "Quyen cho AI Engine thao tac CloudWatch, DynamoDB va Bedrock"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # CloudWatch Logs
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        # DynamoDB Incident Table
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:Query",
          "dynamodb:UpdateItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.incidents.arn
      },
      {
        # Amazon Bedrock (goi Claude) va Marketplace de check model subscription
        Action = [
          "bedrock:InvokeModel",
          "aws-marketplace:ViewSubscriptions",
          "aws-marketplace:Subscribe"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ai_engine_attach" {
  role       = aws_iam_role.ai_engine_lambda.name
  policy_arn = aws_iam_policy.ai_engine_policy.arn
}

# 3. Zip code Lambda
data "archive_file" "ai_engine_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/ai_engine"
  output_path = "${path.module}/lambda/ai_engine_payload.zip"
}

# 4. Lambda Function
resource "aws_lambda_function" "ai_engine" {
  function_name    = "${var.project_name}-ai-engine"
  role             = aws_iam_role.ai_engine_lambda.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.ai_engine_zip.output_path
  source_code_hash = data.archive_file.ai_engine_zip.output_base64sha256
  timeout          = 300 # Thoi gian doi Bedrock API (5 phut)
  memory_size      = 256 # Du de xu ly logs

  environment {
    variables = {
      ES_URL             = var.elasticsearch_url
      ES_USERNAME        = var.elasticsearch_username
      ES_PASSWORD        = var.elasticsearch_password
      ES_VERIFY_SSL      = "false"
      DYNAMODB_TABLE     = aws_dynamodb_table.incidents.name
      BEDROCK_REGION     = var.bedrock_region
      BEDROCK_MODEL_ID   = var.bedrock_model_id
      TELEGRAM_BOT_TOKEN = var.telegram_bot_token
      TELEGRAM_CHAT_ID   = var.telegram_chat_id
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.ai_engine_attach
  ]
}

# 5. Lambda Function URL (Public Endpoint de Kibana goi Webhook)
resource "aws_lambda_function_url" "ai_engine_url" {
  function_name      = aws_lambda_function.ai_engine.function_name
  authorization_type = "NONE" # Cho phep Kibana goi truc tiep (co the cai thien bang IAM sau neu can)
}

resource "aws_lambda_permission" "ai_engine_url" {
  statement_id           = "AllowFunctionURLInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.ai_engine.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

output "ai_engine_webhook_url" {
  value       = aws_lambda_function_url.ai_engine_url.function_url
  description = "URL de cau hinh trong Kibana Webhook Connector"
}
