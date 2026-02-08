#!/bin/bash
# Complete Rook-Ceph setup script for k3d
#
# This script:
#   1. Creates a k3d cluster optimized for Rook
#   2. Installs the Rook operator
#   3. Creates a Ceph cluster with PVC-backed OSDs
#   4. Deploys the toolbox for management
#   5. Creates block and filesystem storage classes
#
# Usage:
#   ./setup-k3d-rook.sh

set -e

CLUSTER_NAME="rook-lab"
ROOK_VERSION="v1.14.0"
STORAGE_DIR="${HOME}/k3d-rook-storage"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=============================================="
echo "  Rook-Ceph Setup for k3d"
echo "=============================================="
echo ""

# Check prerequisites
echo "Checking prerequisites..."
for cmd in docker k3d kubectl git; do
    if ! command -v $cmd &> /dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done
echo "All prerequisites met."
echo ""

# Check if cluster exists
if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
    read -p "Delete and recreate? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster..."
        k3d cluster delete ${CLUSTER_NAME}
        rm -rf "${STORAGE_DIR}"
    else
        echo "Using existing cluster. Skipping to Rook installation..."
        kubectl config use-context k3d-${CLUSTER_NAME}
    fi
fi

# Create storage directory
mkdir -p "${STORAGE_DIR}"

# Step 1: Create k3d cluster
if ! k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    echo ""
    echo "Step 1: Creating k3d cluster..."
    k3d cluster create ${CLUSTER_NAME} \
        --servers 1 \
        --agents 3 \
        --volume "${STORAGE_DIR}:/var/lib/rancher/k3s/storage@all" \
        --volume "${STORAGE_DIR}/rook:/var/lib/rook@all" \
        --port "30000-30100:30000-30100@server:0" \
        --k3s-arg "--disable=traefik@server:0"

    echo "Waiting for nodes to be ready..."
    kubectl wait --for=condition=ready nodes --all --timeout=120s
fi

echo ""
echo "Cluster nodes:"
kubectl get nodes -o wide
echo ""

# Step 2: Clone Rook repository
ROOK_DIR="/tmp/rook-${ROOK_VERSION}"
if [ ! -d "${ROOK_DIR}" ]; then
    echo "Step 2: Cloning Rook repository..."
    git clone --single-branch --branch ${ROOK_VERSION} https://github.com/rook/rook.git ${ROOK_DIR}
else
    echo "Step 2: Using existing Rook repository at ${ROOK_DIR}"
fi

cd ${ROOK_DIR}/deploy/examples

# Step 3: Install Rook operator
echo ""
echo "Step 3: Installing Rook operator..."

kubectl create -f crds.yaml 2>/dev/null || kubectl apply -f crds.yaml
kubectl create -f common.yaml 2>/dev/null || kubectl apply -f common.yaml
kubectl create -f operator.yaml 2>/dev/null || kubectl apply -f operator.yaml

echo "Waiting for Rook operator to be ready..."
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-operator --timeout=300s

echo ""
echo "Rook operator is ready:"
kubectl -n rook-ceph get pods -l app=rook-ceph-operator
echo ""

# Step 4: Create Ceph cluster
echo "Step 4: Creating Ceph cluster with PVC-backed OSDs..."
kubectl apply -f ${SCRIPT_DIR}/cluster-k3d-pvc.yaml

echo ""
echo "Waiting for Ceph cluster to initialize..."
echo "This may take several minutes. Watch progress with:"
echo "  kubectl -n rook-ceph get pods -w"
echo ""

# Wait for mon
echo "Waiting for monitor..."
timeout 300 bash -c 'until kubectl -n rook-ceph get pod -l app=rook-ceph-mon -o jsonpath="{.items[0].status.phase}" 2>/dev/null | grep -q Running; do sleep 5; done' || {
    echo "WARNING: Monitor not ready after 5 minutes. Check logs with:"
    echo "  kubectl -n rook-ceph logs -l app=rook-ceph-operator"
}

# Wait for mgr
echo "Waiting for manager..."
timeout 180 bash -c 'until kubectl -n rook-ceph get pod -l app=rook-ceph-mgr -o jsonpath="{.items[0].status.phase}" 2>/dev/null | grep -q Running; do sleep 5; done' || {
    echo "WARNING: Manager not ready after 3 minutes."
}

# Wait for OSDs
echo "Waiting for OSDs (this takes a while)..."
timeout 600 bash -c 'until [ $(kubectl -n rook-ceph get pod -l app=rook-ceph-osd --no-headers 2>/dev/null | grep Running | wc -l) -ge 1 ]; do sleep 10; done' || {
    echo "WARNING: OSDs not ready after 10 minutes."
}

echo ""
echo "Current pod status:"
kubectl -n rook-ceph get pods
echo ""

# Step 5: Deploy toolbox
echo "Step 5: Deploying Ceph toolbox..."
kubectl apply -f toolbox.yaml
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-tools --timeout=120s

# Step 6: Create storage classes
echo ""
echo "Step 6: Creating storage classes..."

# Block storage
kubectl apply -f ${SCRIPT_DIR}/04-block-storage/cephblockpool.yaml 2>/dev/null || true
kubectl apply -f ${SCRIPT_DIR}/04-block-storage/storageclass.yaml 2>/dev/null || true

echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Check cluster health:"
echo "  kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status"
echo ""
echo "Storage classes available:"
kubectl get storageclass
echo ""
echo "Dashboard access (if enabled):"
echo "  kubectl -n rook-ceph port-forward svc/rook-ceph-mgr-dashboard 7000:7000"
echo "  Open: https://localhost:7000"
echo "  Get password: kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath='{.data.password}' | base64 -d"
echo ""
echo "Test block storage:"
echo "  kubectl apply -f ${SCRIPT_DIR}/04-block-storage/test-app.yaml"
echo ""
echo "Cleanup when done:"
echo "  k3d cluster delete ${CLUSTER_NAME}"
echo "  rm -rf ${STORAGE_DIR}"
