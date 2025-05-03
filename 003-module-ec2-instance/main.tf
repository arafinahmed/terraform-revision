provider "aws" {
  region = "us-east-1"
}

module "ec2-instance" {
  source        = "./modules/ec2-instance"
  ami_value     = var.ami_value
  instance_type = var.instance_type
}