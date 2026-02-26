variable "vpc_cidr" {}
variable "env_prefix" {}

# This module simulates a standard 3-tier VPC architecture

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.env_prefix}-shopmicro-vpc"
  }
}

# In a real environment we would output IDs of created subnets and VPCs
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = [] # Placeholder 
}

output "private_subnets" {
  value = [] # Placeholder
}
