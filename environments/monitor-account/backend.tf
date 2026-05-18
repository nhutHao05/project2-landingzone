terraform {
  backend "s3" {
    bucket       = "p1-bootstrap-apse1-tfstate"
    key          = "landing-zone/monitor-account/terraform.tfstate"
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
