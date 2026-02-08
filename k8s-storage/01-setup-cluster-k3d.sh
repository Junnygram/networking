#!/bin/bash
# Setup k3d cluster for storage labs
#
# k3d uses k3s which includes local-path-provisioner by default.
# This provides dynamic provisioning out of the box.

set -e

CLUSTER_NAME="storage-lab"
STORAGE_DIR="${HOME}/k3d-storage/${CLUSTER_NAME}"

echo "=== Setting up k3d cluster for storage labs ==="
echo ""

# Check if k3d is installed
if ! command -v k3d &> /dev/null; then
    echo "k3d not found. Installing..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

# Check if cluster already exists
if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        k3d cluster delete ${CLUSTER_NAME}
        rm -rf "${STORAGE_DIR}"
    else
        echo "Using existing cluster."
        kubectl cluster-info --context k3d-${CLUSTER_NAME}
        exit 0
    fi
fi

# Create storage directory for persistent data
echo "Creating storage directory at ${STORAGE_DIR}..."
mkdir -p "${STORAGE_DIR}"

# Create cluster with storage volume mounts
echo ""
echo "Creating k3d cluster with 1 server and 3 agents..."
k3d cluster create ${CLUSTER_NAME} \
    --servers 1 \
    --agents 3 \
    --volume "${STORAGE_DIR}:/var/lib/rancher/k3s/storage@all" \
    --port "30000-30100:30000-30100@server:0" \
    --k3s-arg "--disable=traefik@server:0"

# Wait for nodes to be ready
echo ""
echo "Waiting for nodes to be ready..."
kubectl wait --for=condition=ready nodes --all --timeout=120s

# Verify nodes
echo ""
echo "=== Cluster Nodes ==="
kubectl get nodes -o wide

# Verify StorageClass (k3s provides local-path by default)
echo ""
echo "=== Storage Classes ==="
kubectl get storageclass

# The local-path StorageClass should already be default
# Verify it's set as default
if ! kubectl get storageclass local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' | grep -q "true"; then
    echo "Setting local-path as default StorageClass..."
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
fi

# Create directories on agent nodes for hostPath demos
echo ""
echo "Creating storage directories on agent nodes..."
for node in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep agent); do
    echo "Setting up ${node}..."
    docker exec ${node} mkdir -p /mnt/data
    docker exec ${node} chmod 777 /mnt/data
done

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Cluster '${CLUSTER_NAME}' is ready!"
echo ""
echo "Storage features:"
echo "  - local-path StorageClass (default) - dynamic provisioning"
echo "  - Host storage mapped to: ${STORAGE_DIR}"
echo ""
echo "Quick verification:"
echo "  kubectl get nodes"
echo "  kubectl get storageclass"
echo ""
echo "Test dynamic provisioning:"
echo "  kubectl apply -f 03-dynamic-provisioning/02-dynamic-pvc.yaml"
echo ""
echo "Next steps:"
echo "  1. Follow the exercises in README.md"
echo "  2. For Rook-Ceph, see 06-rook-ceph/k3d-guide.md"
