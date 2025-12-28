variable "aws_region" {
  description = "The AWS region to deploy resources in."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "The EC2 instance type."
  type        = string
  default     = "t2.micro"
}

variable "ami_id" {
  description = "The AMI ID for the EC2 instance. This is an Ubuntu 22.04 LTS AMI for us-east-1."
  type        = string
  default     = "ami-0c55b159cbfafe1f0"
}

variable "key_name" {
  description = "Name of the EC2 key pair to use. Ensure this key exists in the specified AWS region."
  type        = string
  default     = "tech4dev"
}
