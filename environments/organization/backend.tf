terraform {
  backend "s3" {
    bucket       = "p1-bootstrap-apse1-tfstate"
    key          = "landing-zone/terraform.tfstate" # Quản lý tập trung toàn bộ hạ tầng Landing Zone
    region       = "ap-southeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
