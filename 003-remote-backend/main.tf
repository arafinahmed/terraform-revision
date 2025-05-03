provider "aws" {
  region = "us-east-1"
}

resource "aws_instance" "instance1" {
  ami = "ami-0f88e80871fd81e91"
  instance_type = "t2.micro"
}