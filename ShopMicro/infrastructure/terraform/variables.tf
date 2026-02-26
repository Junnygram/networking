variable "aws_region" {
  description = "AWS region for deployments"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "aws_access_key" {
  description = "AWS Access Key"
  type        = string
  sensitive   = true
  default     = "AKIAUPMYNOFLCMLVUIW3"
}

variable "aws_secret_key" {
  description = "AWS Secret Key"
  type        = string
  sensitive   = true
  default     = "oO3+TDCxVtdEiuV4UKvwl5e870ZDm+hAzq5KPPt4"
}
