variable "vpc_id" {}
variable "public_subnets" {}
variable "private_subnets" {}
variable "instance_type" {}
variable "env_prefix" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical Ubuntu

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "k8s_ssh_key" {
  key_name   = "${var.env_prefix}-shopmicro-key"
  public_key = file("${path.module}/../../shopmicro-key.pub")
}

resource "aws_security_group" "nodes_sg" {
  name        = "${var.env_prefix}-k8s-nodes-sg"
  description = "Security group for self-hosted k8s nodes"
  vpc_id      = var.vpc_id

  # Allow SSH for Ansible
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Kubernetes API Server
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTP Ingress
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Kubernetes NodePorts (Grafana, Prometheus, etc)
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all internal communication
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "k8s_master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.nodes_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.k8s_ssh_key.key_name

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Wait for network to be ready
              sleep 5

              # Fetch public IP with retries
              for i in {1..5}; do
                PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
                if [ -n "$PUBLIC_IP" ]; then
                  echo "Public IP: $PUBLIC_IP" >> /var/log/k3s-install.log
                  break
                fi
                sleep 2
              done

              # Install K3s with public IP in TLS SANs
              curl -sfL https://get.k3s.io | sh -s - server \
                --cluster-init \
                --write-kubeconfig-mode 644 \
                --tls-san "$PUBLIC_IP" \
                --tls-san "$(hostname -I | awk '{print $1}')" 2>&1 | tee -a /var/log/k3s-install.log

              echo "K3s installation complete" >> /var/log/k3s-install.log
              EOF

  tags = {
    Name = "${var.env_prefix}-k8s-master"
    Role = "master"
  }
}

resource "aws_instance" "k8s_worker" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.public_subnets[0] # Keeping them in public for easy ansible SSH connecting
  vpc_security_group_ids      = [aws_security_group.nodes_sg.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.k8s_ssh_key.key_name

  # Wait for master, retrieve token, and join
  user_data = <<-EOF
              #!/bin/bash
              sleep 60
              # In a perfect world we pass the token securely, but for this quick demo loop we assume k3s master IP
              MASTER_IP=${aws_instance.k8s_master.private_ip}
              # Typically requires master token which we would fetch via ssh or SSM,
              # but as a single node fallback we will install agent mode connecting to it manually later via Makefile.
              EOF

  tags = {
    Name = "${var.env_prefix}-k8s-worker"
    Role = "worker"
  }
}

output "master_public_ip" {
  value = aws_instance.k8s_master.public_ip
}

output "worker_public_ip" {
  value = aws_instance.k8s_worker.public_ip
}
