#!/bin/bash
# Cleanup script for storage labs
# Supports both k3d and KinD clusters

set -e

CLUSTER_NAME="storage-lab"

echo "=== Cleaning up Storage Lab Resources ==="

# Detect which cluster tool is being used
K3D_CLUSTER_EXISTS=false
KIND_CLUSTER_EXISTS=false

if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
    K3D_CLUSTER_EXISTS=true
fi

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    KIND_CLUSTER_EXISTS=true
fi

if [ "$K3D_CLUSTER_EXISTS" = false ] && [ "$KIND_CLUSTER_EXISTS" = false ]; then
    echo "Cluster '${CLUSTER_NAME}' does not exist. Nothing to clean up."
    exit 0
fi

# Switch to the right context
if [ "$K3D_CLUSTER_EXISTS" = true ]; then
    kubectl config use-context k3d-${CLUSTER_NAME} 2>/dev/null || true
    STORAGE_DIR="${HOME}/k3d-storage/${CLUSTER_NAME}"
else
    kubectl config use-context kind-${CLUSTER_NAME} 2>/dev/null || true
fi

echo "Deleting all lab resources..."

# Delete resources in reverse order of creation
echo "- Deleting pods..."
kubectl delete pods --all --ignore-not-found 2>/dev/null || true

echo "- Deleting StatefulSets..."
kubectl delete statefulsets --all --ignore-not-found 2>/dev/null || true

echo "- Deleting Deployments..."
kubectl delete deployments --all --ignore-not-found 2>/dev/null || true

echo "- Deleting Services..."
kubectl delete services --all --ignore-not-found 2>/dev/null || true

echo "- Deleting PVCs..."
kubectl delete pvc --all --ignore-not-found 2>/dev/null || true

echo "- Deleting PVs..."
kubectl delete pv --all --ignore-not-found 2>/dev/null || true

echo "- Deleting custom StorageClasses..."
kubectl delete storageclass --ignore-not-found \
    retain-storage-class \
    delete-storage-class \
    immediate-storage-class \
    expandable-storage-class \
    2>/dev/null || true

# Clean up Rook-Ceph if installed
if kubectl get namespace rook-ceph &>/dev/null; then
    echo "- Cleaning up Rook-Ceph..."
    kubectl delete -n rook-ceph cephcluster --all --ignore-not-found 2>/dev/null || true
    kubectl delete -n rook-ceph cephblockpool --all --ignore-not-found 2>/dev/null || true
    kubectl delete -n rook-ceph cephfilesystem --all --ignore-not-found 2>/dev/null || true
    kubectl delete -n rook-ceph cephobjectstore --all --ignore-not-found 2>/dev/null || true

    # Wait for cleanup
    sleep 5

    kubectl delete namespace rook-ceph --ignore-not-found 2>/dev/null || true
fi

echo ""
if [ "$K3D_CLUSTER_EXISTS" = true ]; then
    read -p "Delete the k3d cluster '${CLUSTER_NAME}'? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting k3d cluster..."
        k3d cluster delete ${CLUSTER_NAME}
        # Clean up storage directory
        if [ -d "$STORAGE_DIR" ]; then
            rm -rf "$STORAGE_DIR"
            echo "Removed storage directory: $STORAGE_DIR"
        fi
        echo "Cluster deleted."
    else
        echo "Cluster preserved. Resources cleaned up."
    fi
elif [ "$KIND_CLUSTER_EXISTS" = true ]; then
    read -p "Delete the KinD cluster '${CLUSTER_NAME}'? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting KinD cluster..."
        kind delete cluster --name ${CLUSTER_NAME}
        echo "Cluster deleted."
    else
        echo "Cluster preserved. Resources cleaned up."
    fi
fi

echo ""
echo "=== Cleanup Complete ==="
