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
  iam_instance_profile        = aws_iam_instance_profile.k8s_node_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # Force resize root partition to use full 20GB volume
              # (Important if AMI defaults to 8GB)
              sudo growpart /dev/nvme0n1 1 || true
              sudo resize2fs /dev/nvme0n1p1 || true

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

              # Wait for K3s API to become ready
              sleep 10
              export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
              
              # Install AWS CLI to get ECR token
              snap install aws-cli --classic
              
               # Create secrets in both namespaces
              for NS in shopmicro argocd; do
                kubectl create namespace $NS 2>/dev/null || true
                kubectl delete secret ecr-cred -n $NS 2>/dev/null || true
                kubectl create secret docker-registry ecr-cred \
                  --docker-server=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com \
                  --docker-username=AWS \
                  --docker-password=$TOKEN -n $NS
              done
                
              # Patch default service account so all pods use this secret automatically
              kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ecr-cred"}]}' -n shopmicro

              # Add script to cron to refresh every 6 hours
              cat << 'CRONSCRIPT' > /usr/local/bin/refresh-ecr.sh
              #!/bin/bash
              export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
              REGION="us-east-1"
              ACCOUNT_ID=$(/snap/bin/aws sts get-caller-identity --query Account --output text)
              TOKEN=$(/snap/bin/aws ecr get-login-password --region $REGION)
               for NS in shopmicro argocd; do
                kubectl create namespace $NS 2>/dev/null || true
                kubectl delete secret ecr-cred -n $NS 2>/dev/null || true
                kubectl create secret docker-registry ecr-cred \
                  --docker-server=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com \
                  --docker-username=AWS \
                  --docker-password=$TOKEN -n $NS
              done
              kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ecr-cred"}]}' -n shopmicro
              kubectl patch serviceaccount default -p '{"imagePullSecrets":[{"name":"ecr-cred"}]}' -n argocd
              CRONSCRIPT
              chmod +x /usr/local/bin/refresh-ecr.sh
              echo "0 */6 * * * root /usr/local/bin/refresh-ecr.sh" > /etc/cron.d/ecr-refresh
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
  iam_instance_profile        = aws_iam_instance_profile.k8s_node_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  # Wait for master, retrieve token, and join
  user_data = <<-EOF
              #!/bin/bash
              # Force resize root partition
              sudo growpart /dev/nvme0n1 1 || true
              sudo resize2fs /dev/nvme0n1p1 || true
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
