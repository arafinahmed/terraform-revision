   provider "aws" {
     region = "us-east-1"  # Set your desired AWS region
   }

   resource "aws_instance" "example" {
     ami           = "ami-0f88e80871fd81e91"  # Specify an appropriate AMI ID
     instance_type = "t2.micro"
   }