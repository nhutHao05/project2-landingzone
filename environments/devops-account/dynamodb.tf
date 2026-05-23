resource "aws_dynamodb_table" "soar_incidents" {
  name         = "p2-soar-incidents"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"

  attribute {
    name = "incident_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name = "p2-soar-incidents"
  }
}
