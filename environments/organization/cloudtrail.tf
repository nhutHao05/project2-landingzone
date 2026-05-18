resource "aws_cloudtrail" "organization" {
  count                         = var.enable_org_cloudtrail ? 1 : 0
  name                          = var.org_trail_name
  s3_bucket_name                = var.centralized_logs_bucket_name
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = true
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  lifecycle {
    precondition {
      condition     = var.centralized_logs_bucket_name != ""
      error_message = "centralized_logs_bucket_name must be set when enable_org_cloudtrail is true."
    }
  }

  tags = {
    Name        = var.org_trail_name
    Project     = var.project_name
    Environment = "security"
    ManagedBy   = "Terraform"
  }
}
