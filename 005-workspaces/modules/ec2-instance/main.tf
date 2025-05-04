provider "aws" {
  region = "us-east-1"  # Replace with your desired AWS region.
}

variable "ami" {
  description = "AMI ID"
  type        = string
}

variable "instance_type" {
  description = "Instance type"
  type        = string
}

resource "aws_instance" "my-instance" {
  ami = var.ami
  instance_type = var.instance_type
}