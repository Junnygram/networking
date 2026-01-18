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

# Download join command from S3 and join the cluster
echo "Waiting for join command to appear in S3..."
while ! aws s3 cp s3://${s3_bucket}/join-command.sh /home/ubuntu/join-command.sh; do
    echo "Join command not ready yet. Retrying in 10 seconds..."
    sleep 10
done

chmod +x /home/ubuntu/join-command.sh
/home/ubuntu/join-command.sh