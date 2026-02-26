variable "vpc_id" {}
variable "private_subnets" {}
variable "env_prefix" {}

# Simulate RDS / ElastiCache Data Layer Provisioning
# In this assignment PostgreSQL & Redis run in K8s, 
# but a production architecture may externalize them.

# resource "aws_db_instance" "postgres_primary" { ... }
# resource "aws_elasticache_cluster" "redis_cache" { ... }
