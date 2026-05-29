# ==========================================
# Amazon Inspector Findings -> Monitor SQS
# ==========================================
# Inspector findings are emitted in the DevOps account where EC2 workloads run.
# The SQS target ARN is created by the monitor-account stack.

data "aws_caller_identity" "current" {}

resource "aws_inspector2_enabler" "ec2" {
  count = var.enable_inspector_ec2_scanning ? 1 : 0

  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["EC2"]
}

resource "aws_cloudwatch_event_rule" "inspector_findings_to_monitor" {
  count = local.inspector_findings_queue_arn != "" ? 1 : 0

  name        = "${var.project}-inspector-findings-to-monitor"
  description = "Forward Critical and High Amazon Inspector findings to the Monitor account SQS queue"

  event_pattern = jsonencode({
    source      = ["aws.inspector2"]
    detail-type = ["Inspector2 Finding"]
    detail = {
      severity = ["CRITICAL", "HIGH"]
      status   = ["ACTIVE"]
    }
  })
}

resource "aws_cloudwatch_event_target" "inspector_findings_to_monitor_sqs" {
  count = local.inspector_findings_queue_arn != "" ? 1 : 0

  rule = aws_cloudwatch_event_rule.inspector_findings_to_monitor[0].name
  arn  = local.inspector_findings_queue_arn
}
