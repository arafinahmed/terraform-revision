provider "aws" {
  region = "us-east-1"  # Replace with your desired AWS region.
}

variable "ami" {
  description = "AMI ID"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = map(string)

  default = {
    "dev" = "t2.micro"
    "prod" = "t2.medium"
  }
}

module "ec2_instance" {
  source        = "./modules/ec2-instance"
  ami           = var.ami
  instance_type = lookup(var.instance_type, terraform.workspace, "t2.medium")  # Default to t2.micro if not found
}