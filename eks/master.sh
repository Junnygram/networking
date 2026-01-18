#!/bin/bash
set -x

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

# Install dependencies
apt-get update
apt-get install -y docker.io apt-transport-https ca-certificates curl awscli

# Install Kubernetes components
mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Initialize Kubernetes cluster
kubeadm init --pod-network-cidr=192.168.0.0/16

# Set up kubeconfig for the ubuntu user
mkdir -p /home/ubuntu/.kube
cp -i /etc/kubernetes/admin.conf /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube

# Install Calico CNI
kubectl --kubeconfig /etc/kubernetes/admin.conf create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml
kubectl --kubeconfig /etc/kubernetes/admin.conf create -f https://docs.projectcalico.org/manifests/custom-resources.yaml

# Generate join command and upload to S3
kubeadm token create --print-join-command > /home/ubuntu/join-command.sh
aws s3 cp /home/ubuntu/join-command.sh s3://${s3_bucket}/join-command.sh