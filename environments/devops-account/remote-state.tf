data "terraform_remote_state" "monitor" {
  backend = "s3"

  config = {
    bucket = var.monitor_tfstate_bucket
    key    = var.monitor_tfstate_key
    region = var.monitor_tfstate_region
  }
}

locals {
  inspector_findings_queue_arn = var.monitor_inspector_findings_queue_arn != "" ? var.monitor_inspector_findings_queue_arn : try(data.terraform_remote_state.monitor.outputs.sqs_inspector_queue_arn, "")
}
