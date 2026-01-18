# This is a self-hosted Kubernetes cluster configuration using kubeadm.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.40.0"
    }
  }
}

provider "aws" {
  region     = var.aws-region
  access_key = var.access_key
  secret_key = var.secret_key
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.5.2"

  name = "kubeadm-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws-region}a", "${var.aws-region}b", "${var.aws-region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

resource "aws_s3_bucket" "k8s_join_command" {
  bucket = "k8s-join-command-${random_id.id.hex}"
}

resource "random_id" "id" {
  byte_length = 8
}

resource "aws_iam_role" "k8s_role" {
  name = "k8s-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "s3_access" {
  name        = "s3-access"
  description = "Allow access to the S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
        ]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.k8s_join_command.arn}/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_access_attachment" {
  role       = aws_iam_role.k8s_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

resource "aws_iam_instance_profile" "k8s_instance_profile" {
  name = "k8s-instance-profile"
  role = aws_iam_role.k8s_role.name
}

resource "aws_security_group" "k8s_sg" {
  name        = "k8s-sg"
  description = "Security group for Kubernetes cluster"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "k8s_key" {
  key_name   = "k8s-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDW3C7Mlrc1ADCGvpt0pirM4xFtYcXKdhPaCgfZEAyhQ+X9LADyyvdysr7ZspawF1nG/NQHCZDEvD+q05DiG4IneU59C/apfhoNWBPzVvni0O3X02La5JJNsPN1UgAP3W0YwmSBPrqKiZR1YDYgkyxuPeAh6bRCNuSihnz9VZfNEQK4LVlE4K85f8i0T3+Ghv98ddUf+ZzP32DshOOe+PyZwqlIKdM3Rj7jKQq2CKxzP+038W33HeH5hubeP8KSaQR+clJ5WSfCldEJZzZ5t3QBtmUxabRtUHb+40kpBzkSdC1kI0cxuYt5FCuFMzeyhK7XHR/qrU8/pDIy5NGYN1vSK5V2qsu/S0vgk0XdKxJFh8Y75TiEqtd/Ojo9gT4bZ1aj40j0XK+ezW4NLla8DIDfwGB24RqfyYwmesb9btFWoI03/j1U4QHwzbqA1RaXFnXISeDqjvPG+7cuv8Ky8om2rn3Mp5Vf5AD0eRp7zbQhALjByc2AzscQh+ZHodZDZhF9qAsxHTUXwuq0YOfyTDBtRFkd41FbOivqdqM0zau1lWP95c/j5MjbjPQLix8zLY6XaOPckVPB78yYgR4AnZeG2H78Zm2KQjSgFOUC7rnnF7sWtheFz8cYG+yn4qCdl70fmTw6LqF38NC1xhExjI852S2miQjt8Yz8k9ge0Gr6fw== junioroyewunmi@Junnys-MacBook-Air.local"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "master" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.k8s_key.key_name
  subnet_id     = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile = aws_iam_instance_profile.k8s_instance_profile.name
  user_data     = templatefile("master.sh", { s3_bucket = aws_s3_bucket.k8s_join_command.bucket })
  associate_public_ip_address = true

  provisioner "remote-exec" {
    inline = [
      "echo '${aws_key_pair.k8s_key.public_key}' >> /home/ubuntu/.ssh/authorized_keys"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("k8s-key")
      host        = self.public_ip
    }
  }

  tags = {
    Name = "master_node"
  }
}

resource "aws_instance" "worker" {
  count         = 3
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  key_name      = aws_key_pair.k8s_key.key_name
  subnet_id     = module.vpc.public_subnets[1 + (count.index % (length(module.vpc.public_subnets) - 1))]
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile = aws_iam_instance_profile.k8s_instance_profile.name
  user_data     = templatefile("worker.sh", { s3_bucket = aws_s3_bucket.k8s_join_command.bucket })
  associate_public_ip_address = true

  tags = {
    Name = "worker_node_${count.index}"
  }
}

output "master_public_ip" {
  value = aws_instance.master.public_ip
}

output "ssh_command" {
  value = "ssh -i k8s-key ubuntu@${aws_instance.master.public_ip}"
}

output "private_key" {
  value = file("k8s-key")
  sensitive = true
}