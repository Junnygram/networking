# Configure the AWS Provider
provider "aws" {
  region = var.aws_region
}

# Define the S3 backend for Terraform state
terraform {
  backend "s3" {
    # The bucket name will be passed via the command line in the GitHub Actions workflow.
    # bucket  = "your-terraform-state-bucket-name" 
    key     = "global/s3/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}

# Data source to get the default VPC
data "aws_vpc" "default" {
  default = true
}

# Security group to allow HTTP and SSH traffic
resource "aws_security_group" "web_sg" {
  name        = "web-server-sg"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "web-server-sg"
  }
}

# EC2 Instance
resource "aws_instance" "web_server" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name
  security_groups = [aws_security_group.web_sg.name]

  # User data script to install Docker and Docker Compose
  user_data = <<-EOF
              #!/bin/bash
              # Update and install prerequisites
              sudo apt-get update -y
              sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common

              # Add Docker's official GPG key
              curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

              # Add Docker repository
              sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

              # Install Docker
              sudo apt-get update -y
              sudo apt-get install -y docker-ce

              # Add ubuntu user to the docker group to run docker commands without sudo
              sudo usermod -aG docker ubuntu

              # Install Docker Compose
              sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              sudo chmod +x /usr/local/bin/docker-compose
              
              # Ensure docker service is started and enabled
              sudo systemctl start docker
              sudo systemctl enable docker
              EOF

  tags = {
    Name = "WebApp-Server"
  }
}

# ECR Repository for Frontend App
resource "aws_ecr_repository" "frontend_app_repo" {
  name                 = "frontend-app"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ECR Repository for Backend Service
resource "aws_ecr_repository" "backend_service_repo" {
  name                 = "backend-service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Output the ECR repository URLs for use in CI/CD
output "frontend_app_ecr_repo_url" {
  description = "The URL of the ECR repository for the frontend-app."
  value       = aws_ecr_repository.frontend_app_repo.repository_url
}

output "backend_service_ecr_repo_url" {
  description = "The URL of the ECR repository for the backend-service."
  value       = aws_ecr_repository.backend_service_repo.repository_url
}

# Output the public IP of the EC2 instance
output "instance_public_ip" {
  description = "The public IP address of the web server instance."
  value       = aws_instance.web_server.public_ip
}
