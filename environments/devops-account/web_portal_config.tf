resource "local_file" "web_portal_config" {
  content = jsonencode({
    API_GATEWAY_URL = "${aws_api_gateway_stage.remediation_stage.invoke_url}/remediate"
  })
  filename = "${path.module}/../../web-portal/config.json"
}
