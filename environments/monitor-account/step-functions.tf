# ==========================================
# AWS Step Functions — Remediation Orchestrator (Phase 6)
# ==========================================
# State Machine điều phối remediation workflow:
# - Auto-execute cho low-risk actions
# - Human-in-the-loop (TaskToken) cho high-risk actions
# - Tích hợp với Cognito-authenticated Web Portal

# ---------- IAM Role cho Step Functions ----------
resource "aws_iam_role" "sfn_remediation" {
  name = "${var.project_name}-sfn-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "sfn_remediation" {
  name = "${var.project_name}-sfn-remediation-policy"
  role = aws_iam_role.sfn_remediation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.remediation_executor.arn,
          "${aws_lambda_function.remediation_executor.arn}:*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------- Lambda: Remediation Executor ----------
# Lambda riêng chỉ thực thi remediation actions (isolate_ec2, revoke_creds, block_ip)
data "archive_file" "remediation_executor_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/remediation_executor"
  output_path = "${path.module}/lambda/remediation_executor_payload.zip"
}

resource "aws_iam_role" "remediation_executor" {
  name = "${var.project_name}-remediation-executor-role"

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

resource "aws_iam_role_policy" "remediation_executor" {
  name = "${var.project_name}-remediation-executor-policy"
  role = aws_iam_role.remediation_executor.id

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
        Sid    = "AllowDynamoDBUpdate"
        Effect = "Allow"
        Action = [
          "dynamodb:UpdateItem",
          "dynamodb:GetItem",
          "dynamodb:PutItem"
        ]
        Resource = aws_dynamodb_table.incidents.arn
      },
      {
        Sid      = "AllowDevOpsAssumeRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = local.effective_devops_remediation_role_arn
      }
    ]
  })
}

resource "aws_lambda_function" "remediation_executor" {
  filename         = data.archive_file.remediation_executor_zip.output_path
  source_code_hash = data.archive_file.remediation_executor_zip.output_base64sha256
  function_name    = "${var.project_name}-remediation-executor"
  role             = aws_iam_role.remediation_executor.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 60

  environment {
    variables = {
      DYNAMODB_TABLE              = aws_dynamodb_table.incidents.name
      DEVOPS_REMEDIATION_ROLE_ARN = local.effective_devops_remediation_role_arn
      TELEGRAM_BOT_TOKEN          = var.telegram_bot_token
      TELEGRAM_CHAT_ID            = var.telegram_chat_id
    }
  }

  tags = {
    Name = "${var.project_name}-remediation-executor"
  }
}

# ---------- Lambda: Remediation Callback ----------
# Lambda nhận approve/reject từ Web Portal, gọi SF SendTaskSuccess/Failure
data "archive_file" "remediation_callback_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/remediation_callback"
  output_path = "${path.module}/lambda/remediation_callback_payload.zip"
}

resource "aws_iam_role" "remediation_callback" {
  name = "${var.project_name}-remediation-callback-role"

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

resource "aws_iam_role_policy" "remediation_callback" {
  name = "${var.project_name}-remediation-callback-policy"
  role = aws_iam_role.remediation_callback.id

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
        Sid    = "AllowDynamoDBAccess"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.incidents.arn
      },
      {
        Sid    = "AllowStepFunctionsCallback"
        Effect = "Allow"
        Action = [
          "states:SendTaskSuccess",
          "states:SendTaskFailure"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "remediation_callback" {
  filename         = data.archive_file.remediation_callback_zip.output_path
  source_code_hash = data.archive_file.remediation_callback_zip.output_base64sha256
  function_name    = "${var.project_name}-remediation-callback"
  role             = aws_iam_role.remediation_callback.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.incidents.name
    }
  }

  tags = {
    Name = "${var.project_name}-remediation-callback"
  }
}

# ---------- Step Functions State Machine ----------
resource "aws_sfn_state_machine" "remediation" {
  name     = "${var.project_name}-remediation-workflow"
  role_arn = aws_iam_role.sfn_remediation.arn

  definition = jsonencode({
    Comment = "SOAR Remediation Workflow — Human-in-the-loop"
    StartAt = "ClassifySeverity"
    States = {

      # ① Classify: auto-execute hoặc chờ approval
      ClassifySeverity = {
        Type    = "Choice"
        Comment = "Route based on auto_execute flag from AI Engine"
        Choices = [
          {
            Variable     = "$.auto_execute"
            BooleanEquals = true
            Next         = "ExecuteRemediation"
          }
        ]
        Default = "WaitForApproval"
      }

      # ② Auto-execute path — gọi Lambda executor trực tiếp
      ExecuteRemediation = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.remediation_executor.arn
          Payload = {
            "incident_id.$"  = "$.incident_id"
            "action_type.$"  = "$.action_type"
            "target.$"       = "$.target"
            "source.$"       = "$.source"
            "auto_execute.$" = "$.auto_execute"
          }
        }
        ResultPath = "$.execution_result"
        Next       = "WorkflowComplete"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
      }

      # ③ Human approval — pause with TaskToken
      WaitForApproval = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        Parameters = {
          FunctionName = aws_lambda_function.remediation_executor.arn
          Payload = {
            "incident_id.$"  = "$.incident_id"
            "action_type.$"  = "$.action_type"
            "target.$"       = "$.target"
            "source.$"       = "$.source"
            "task_token.$"   = "$$.Task.Token"
            "wait_for_approval" = true
          }
        }
        TimeoutSeconds = var.sfn_approval_timeout_seconds
        ResultPath     = "$.approval_result"
        Next           = "ApprovalRouter"
        Catch = [
          {
            ErrorEquals = ["States.Timeout"]
            Next        = "HandleTimeout"
            ResultPath  = "$.error"
          },
          {
            ErrorEquals = ["States.TaskFailed"]
            Next        = "RecordRejection"
            ResultPath  = "$.error"
          },
          {
            ErrorEquals = ["States.ALL"]
            Next        = "HandleError"
            ResultPath  = "$.error"
          }
        ]
      }

      # ④ Route based on approval decision
      ApprovalRouter = {
        Type    = "Choice"
        Comment = "Check analyst decision"
        Choices = [
          {
            Variable     = "$.approval_result.decision"
            StringEquals = "approved"
            Next         = "ExecuteApprovedAction"
          }
        ]
        Default = "RecordRejection"
      }

      # ⑤ Execute approved action
      ExecuteApprovedAction = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.remediation_executor.arn
          Payload = {
            "incident_id.$"  = "$.incident_id"
            "action_type.$"  = "$.action_type"
            "target.$"       = "$.target"
            "source.$"       = "$.source"
            "approved_by.$"  = "$.approval_result.approved_by"
            "execute_now"    = true
          }
        }
        ResultPath = "$.execution_result"
        Next       = "WorkflowComplete"
        Catch = [{
          ErrorEquals = ["States.ALL"]
          Next        = "HandleError"
          ResultPath  = "$.error"
        }]
      }

      # ⑥ Record rejection
      RecordRejection = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.remediation_executor.arn
          Payload = {
            "incident_id.$" = "$.incident_id"
            "action_type"   = "reject"
            "target.$"      = "$.target"
          }
        }
        ResultPath = "$.rejection_result"
        Next       = "WorkflowComplete"
      }

      # ⑦ Timeout handler
      HandleTimeout = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.remediation_executor.arn
          Payload = {
            "incident_id.$" = "$.incident_id"
            "action_type"   = "timeout"
            "target.$"      = "$.target"
          }
        }
        ResultPath = "$.timeout_result"
        Next       = "WorkflowComplete"
      }

      # ⑧ Error handler
      HandleError = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.remediation_executor.arn
          Payload = {
            "incident_id.$" = "$.incident_id"
            "action_type"   = "error"
            "target.$"      = "$.target"
            "error.$"       = "$.error"
          }
        }
        ResultPath = "$.error_result"
        Next       = "WorkflowComplete"
      }

      # ⑨ Terminal state
      WorkflowComplete = {
        Type = "Succeed"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn_remediation.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tags = {
    Name = "${var.project_name}-remediation-workflow"
  }
}

resource "aws_cloudwatch_log_group" "sfn_remediation" {
  name              = "/aws/states/${var.project_name}-remediation-workflow"
  retention_in_days = 30
}

# ---------- Outputs ----------
output "sfn_state_machine_arn" {
  value       = aws_sfn_state_machine.remediation.arn
  description = "ARN of the remediation Step Functions state machine"
}

output "remediation_executor_lambda_arn" {
  value       = aws_lambda_function.remediation_executor.arn
  description = "ARN of the remediation executor Lambda"
}

output "remediation_callback_lambda_arn" {
  value       = aws_lambda_function.remediation_callback.arn
  description = "ARN of the remediation callback Lambda"
}
