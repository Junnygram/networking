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
    bucket         = "shopmicro-terraform-state-bucket"
    key            = "platform/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
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
