data "archive_file" "remediation_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/remediation_lambda"
  output_path = "${path.module}/remediation_lambda.zip"
}

resource "aws_iam_role" "remediation_lambda_role" {
  name = "${local.name_prefix}-remediation-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "remediation_lambda_policy" {
  name = "${local.name_prefix}-remediation-lambda-policy"
  role = aws_iam_role.remediation_lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:CreateSecurityGroup",
          "ec2:RevokeSecurityGroupEgress",
          "ec2:ModifyInstanceAttribute"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "iam:ListAccessKeys",
          "iam:UpdateAccessKey"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "wafv2:UpdateIPSet",
          "wafv2:GetIPSet"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:Query"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.soar_incidents.arn
      }
    ]
  })
}

resource "aws_lambda_function" "remediation_lambda" {
  filename         = data.archive_file.remediation_lambda_zip.output_path
  source_code_hash = data.archive_file.remediation_lambda_zip.output_base64sha256
  function_name    = "${local.name_prefix}-remediation"
  role             = aws_iam_role.remediation_lambda_role.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.soar_incidents.name
    }
  }

  tags = {
    Name = "${local.name_prefix}-remediation-lambda"
  }
}

# API Gateway
resource "aws_api_gateway_rest_api" "remediation_api" {
  name        = "${local.name_prefix}-remediation-api"
  description = "API Gateway for SOAR Remediation"
}

resource "aws_api_gateway_resource" "remediation_resource" {
  rest_api_id = aws_api_gateway_rest_api.remediation_api.id
  parent_id   = aws_api_gateway_rest_api.remediation_api.root_resource_id
  path_part   = "remediate"
}

resource "aws_api_gateway_resource" "incidents_resource" {
  rest_api_id = aws_api_gateway_rest_api.remediation_api.id
  parent_id   = aws_api_gateway_rest_api.remediation_api.root_resource_id
  path_part   = "incidents"
}

# OPTIONS method for CORS
resource "aws_api_gateway_method" "remediation_options" {
  rest_api_id   = aws_api_gateway_rest_api.remediation_api.id
  resource_id   = aws_api_gateway_resource.remediation_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "remediation_options_integration" {
  rest_api_id             = aws_api_gateway_rest_api.remediation_api.id
  resource_id             = aws_api_gateway_resource.remediation_resource.id
  http_method             = aws_api_gateway_method.remediation_options.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation_lambda.invoke_arn
}

# POST method for actual request
resource "aws_api_gateway_method" "remediation_post" {
  rest_api_id   = aws_api_gateway_rest_api.remediation_api.id
  resource_id   = aws_api_gateway_resource.remediation_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "remediation_post_integration" {
  rest_api_id             = aws_api_gateway_rest_api.remediation_api.id
  resource_id             = aws_api_gateway_resource.remediation_resource.id
  http_method             = aws_api_gateway_method.remediation_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation_lambda.invoke_arn
}

resource "aws_api_gateway_method" "incidents_options" {
  rest_api_id   = aws_api_gateway_rest_api.remediation_api.id
  resource_id   = aws_api_gateway_resource.incidents_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "incidents_options_integration" {
  rest_api_id             = aws_api_gateway_rest_api.remediation_api.id
  resource_id             = aws_api_gateway_resource.incidents_resource.id
  http_method             = aws_api_gateway_method.incidents_options.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation_lambda.invoke_arn
}

resource "aws_api_gateway_method" "incidents_get" {
  rest_api_id   = aws_api_gateway_rest_api.remediation_api.id
  resource_id   = aws_api_gateway_resource.incidents_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "incidents_get_integration" {
  rest_api_id             = aws_api_gateway_rest_api.remediation_api.id
  resource_id             = aws_api_gateway_resource.incidents_resource.id
  http_method             = aws_api_gateway_method.incidents_get.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.remediation_lambda.invoke_arn
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediation_lambda.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.remediation_api.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "remediation_deployment" {
  depends_on = [
    aws_api_gateway_integration.remediation_options_integration,
    aws_api_gateway_integration.remediation_post_integration,
    aws_api_gateway_integration.incidents_options_integration,
    aws_api_gateway_integration.incidents_get_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.remediation_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.remediation_resource.id,
      aws_api_gateway_resource.incidents_resource.id,
      aws_api_gateway_method.remediation_post.id,
      aws_api_gateway_method.incidents_get.id,
      aws_api_gateway_integration.remediation_post_integration.id,
      aws_api_gateway_integration.incidents_get_integration.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "remediation_stage" {
  deployment_id = aws_api_gateway_deployment.remediation_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.remediation_api.id
  stage_name    = "prod"
}

output "remediation_api_url" {
  value       = "${aws_api_gateway_stage.remediation_stage.invoke_url}/remediate"
  description = "The URL of the remediation API Gateway"
}

output "incidents_api_url" {
  value       = "${aws_api_gateway_stage.remediation_stage.invoke_url}/incidents"
  description = "The URL used by the web portal to fetch live incidents"
}
