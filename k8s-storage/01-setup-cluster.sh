#!/bin/bash
# Setup KinD cluster for storage labs

set -e

CLUSTER_NAME="storage-lab"

echo "=== Setting up KinD cluster for storage labs ==="

# Check if cluster already exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kind delete cluster --name ${CLUSTER_NAME}
    else
        echo "Using existing cluster."
        kubectl cluster-info --context kind-${CLUSTER_NAME}
        exit 0
    fi
fi

# Create cluster config
cat <<EOF > /tmp/kind-storage-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 30000
        hostPort: 30000
        protocol: TCP
      - containerPort: 30001
        hostPort: 30001
        protocol: TCP
  - role: worker
    labels:
      storage-node: "true"
  - role: worker
    labels:
      storage-node: "true"
  - role: worker
    labels:
      storage-node: "true"
EOF

echo "Creating KinD cluster with 1 control-plane and 3 workers..."
kind create cluster --config /tmp/kind-storage-config.yaml

# Wait for nodes to be ready
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=ready nodes --all --timeout=120s

# Verify nodes
echo ""
echo "=== Cluster Nodes ==="
kubectl get nodes -o wide

# Verify default StorageClass (KinD provides local-path-provisioner)
echo ""
echo "=== Storage Classes ==="
kubectl get storageclass

# Create directories on worker nodes for hostPath volumes (for static PV demos)
echo ""
echo "Creating storage directories on worker nodes..."
for node in $(kubectl get nodes -l storage-node=true -o jsonpath='{.items[*].metadata.name}'); do
    echo "Setting up ${node}..."
    docker exec ${node} mkdir -p /mnt/data
    docker exec ${node} chmod 777 /mnt/data
done

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Cluster '${CLUSTER_NAME}' is ready!"
echo ""
echo "Quick verification:"
echo "  kubectl get nodes"
echo "  kubectl get storageclass"
echo ""
echo "Next steps:"
echo "  1. cd 02-fundamentals"
echo "  2. Follow the exercises in README.md"

rm -f /tmp/kind-storage-config.yaml
