#!/bin/bash
# Interactive script to explore PV-PVC binding behavior

set -e

echo "=== PV-PVC Binding Explorer ==="
echo ""
echo "This script demonstrates how Kubernetes binds PVCs to PVs."
echo ""

# Step 1: Show available PVs
echo "Step 1: Current Persistent Volumes"
echo "-----------------------------------"
kubectl get pv -o custom-columns=\
'NAME:.metadata.name,CAPACITY:.spec.capacity.storage,ACCESS:.spec.accessModes[0],STATUS:.status.phase,CLAIM:.spec.claimRef.name,CLASS:.spec.storageClassName'
echo ""

# Step 2: Show PVCs
echo "Step 2: Current Persistent Volume Claims"
echo "-----------------------------------------"
kubectl get pvc -o custom-columns=\
'NAME:.metadata.name,STATUS:.status.phase,VOLUME:.spec.volumeName,CAPACITY:.status.capacity.storage,CLASS:.spec.storageClassName' 2>/dev/null || echo "No PVCs found"
echo ""

# Step 3: Interactive demo
read -p "Press Enter to create a new PVC and watch binding..." -r
echo ""

# Create a test PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-binding-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 750Mi
  storageClassName: manual
EOF

echo ""
echo "Waiting for binding..."
sleep 2

# Show the result
echo ""
echo "After creating PVC:"
echo "-------------------"
kubectl get pv,pvc -o custom-columns=\
'TYPE:.kind,NAME:.metadata.name,CAPACITY:.spec.capacity.storage,STATUS:.status.phase'

echo ""
echo "Notice:"
echo "- The PVC requested 750Mi"
echo "- It bound to the smallest PV that could satisfy the request (1Gi)"
echo "- The 2Gi PV remains Available for other claims"
echo ""

read -p "Press Enter to clean up the test PVC..." -r
kubectl delete pvc test-binding-pvc

echo ""
echo "=== Exploration Complete ==="
