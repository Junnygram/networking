variable "env_prefix" {}

# ECR Repositories — one per microservice
resource "aws_ecr_repository" "backend" {
  name                 = "${var.env_prefix}-shopmicro-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.env_prefix
    Service     = "backend"
  }
}

resource "aws_ecr_repository" "frontend" {
  name                 = "${var.env_prefix}-shopmicro-frontend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.env_prefix
    Service     = "frontend"
  }
}

resource "aws_ecr_repository" "ml_service" {
  name                 = "${var.env_prefix}-shopmicro-ml-service"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Environment = var.env_prefix
    Service     = "ml-service"
  }
}

output "backend_repository_url" {
  value = aws_ecr_repository.backend.repository_url
}

output "frontend_repository_url" {
  value = aws_ecr_repository.frontend.repository_url
}

output "ml_service_repository_url" {
  value = aws_ecr_repository.ml_service.repository_url
}
