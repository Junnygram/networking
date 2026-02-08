#!/bin/bash
# Install Rook-Ceph Operator
#
# This script deploys the Rook operator which manages Ceph clusters.
# Run this AFTER you have a Kubernetes cluster with raw storage ready.

set -e

ROOK_VERSION="v1.14.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Installing Rook-Ceph Operator ${ROOK_VERSION} ==="
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! kubectl cluster-info &>/dev/null; then
    echo "ERROR: Cannot connect to Kubernetes cluster"
    echo "Make sure kubectl is configured correctly"
    exit 1
fi

NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
if [ "$NODE_COUNT" -lt 3 ]; then
    echo "WARNING: Found only ${NODE_COUNT} nodes. Rook-Ceph recommends at least 3 nodes."
    echo "Continuing anyway for testing purposes..."
fi

echo "Cluster info:"
kubectl get nodes -o wide
echo ""

# Clone or update Rook repository
ROOK_DIR="/tmp/rook-${ROOK_VERSION}"
if [ -d "$ROOK_DIR" ]; then
    echo "Using existing Rook repository at ${ROOK_DIR}"
else
    echo "Cloning Rook repository..."
    git clone --single-branch --branch ${ROOK_VERSION} https://github.com/rook/rook.git ${ROOK_DIR}
fi

cd ${ROOK_DIR}/deploy/examples

# Deploy CRDs
echo ""
echo "Step 1: Creating Custom Resource Definitions..."
kubectl create -f crds.yaml 2>/dev/null || kubectl apply -f crds.yaml

# Deploy common resources
echo ""
echo "Step 2: Creating common resources..."
kubectl create -f common.yaml 2>/dev/null || kubectl apply -f common.yaml

# Deploy operator
echo ""
echo "Step 3: Deploying Rook operator..."
kubectl create -f operator.yaml 2>/dev/null || kubectl apply -f operator.yaml

# Wait for operator
echo ""
echo "Step 4: Waiting for operator to be ready..."
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-operator --timeout=300s

echo ""
echo "=== Operator Installation Complete ==="
echo ""
echo "Operator pods:"
kubectl -n rook-ceph get pods -l app=rook-ceph-operator
echo ""
echo "Next steps:"
echo "  1. Review the cluster configuration:"
echo "     cat ${SCRIPT_DIR}/03-cluster.yaml"
echo ""
echo "  2. Apply the cluster configuration:"
echo "     kubectl apply -f ${SCRIPT_DIR}/03-cluster.yaml"
echo ""
echo "  3. Monitor cluster creation:"
echo "     kubectl -n rook-ceph get pods -w"
echo ""
echo "  4. Deploy the toolbox to manage the cluster:"
echo "     kubectl apply -f ${ROOK_DIR}/deploy/examples/toolbox.yaml"
