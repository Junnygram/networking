terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Configured for remote state with locking as per requirements
  backend "s3" {
    bucket         = "shopmicro-terraform-state-bucket-if2z6m"
    key            = "platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# --- Module Invocations ---

module "network" {
  source = "./modules/network"

  vpc_cidr   = "10.0.0.0/16"
  env_prefix = var.environment
}

module "compute" {
  source = "./modules/compute"

  vpc_id          = module.network.vpc_id
  public_subnets  = module.network.public_subnets
  private_subnets = module.network.private_subnets
  instance_type   = "t3.medium"
  env_prefix      = var.environment
}

module "data" {
  source = "./modules/data"

  vpc_id          = module.network.vpc_id
  private_subnets = module.network.private_subnets
  env_prefix      = var.environment
}

module "security" {
  source = "./modules/security"

  vpc_id     = module.network.vpc_id
  env_prefix = var.environment
}

module "ecr" {
  source     = "./modules/ecr"
  env_prefix = var.environment
}

module "oidc" {
  source      = "./modules/oidc"
  env_prefix  = var.environment
  github_repo = "Junnygram/networking"
}

# ---- Outputs (used by Makefile + CI Pipeline) ----
output "k8s_master_ip" {
  value = module.compute.master_public_ip
}

output "k8s_worker_ip" {
  value = module.compute.worker_public_ip
}

output "ecr_backend_url" {
  value = module.ecr.backend_repository_url
}

output "ecr_frontend_url" {
  value = module.ecr.frontend_repository_url
}

output "ecr_ml_service_url" {
  value = module.ecr.ml_service_repository_url
}

output "github_actions_role_arn" {
  value = module.oidc.github_actions_role_arn
}
