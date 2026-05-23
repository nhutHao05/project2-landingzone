resource "local_file" "web_portal_config" {
  content = jsonencode({
    API_GATEWAY_URL   = "${aws_api_gateway_stage.remediation_stage.invoke_url}/remediate"
    INCIDENTS_API_URL = "${aws_api_gateway_stage.remediation_stage.invoke_url}/incidents"
  })
  filename = "${path.module}/../../web-portal/config.json"
}
