#!/bin/bash
# Cleanup Script

echo "Deleting namespace ecommerce..."
kubectl delete namespace ecommerce

echo "Removing Node Labels..."
kubectl label nodes ip-10-0-102-148 environment- storage- tier-
kubectl label nodes ip-10-0-102-152 environment- storage- tier-

echo "Removing Node Taints..."
kubectl taint nodes ip-10-0-102-148 workload-
kubectl taint nodes ip-10-0-102-152 workload-

echo "Please manually remove static pods from worker nodes using SSH:"
echo "ssh ubuntu@<node-ip> 'sudo rm /etc/kubernetes/manifests/monitoring-agent.yaml'"
