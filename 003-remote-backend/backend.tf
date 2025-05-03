terraform {
  backend "s3" {
    bucket = "terraform-arafin-004"
    key    = "arafin/terraform.tfstate"
    region = "us-east-1"
    dynamodb_table = "terraform-lock"
  }
}
