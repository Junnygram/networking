variable "vpc_id" {}
variable "env_prefix" {}

# Security Groups and least privilege network paths
# Restricting Access (No public SSH by default)

resource "aws_security_group" "internal_only" {
  name        = "${var.env_prefix}-internal-only"
  description = "Allow internal VPC traffic only, deny all public"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
