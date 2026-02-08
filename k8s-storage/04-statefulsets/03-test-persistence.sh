#!/bin/bash
# Test StatefulSet persistence

set -e

echo "=== StatefulSet Persistence Test ==="
echo ""

# Check if StatefulSet exists
if ! kubectl get statefulset web &>/dev/null; then
    echo "StatefulSet 'web' not found. Please apply the manifests first:"
    echo "  kubectl apply -f 01-headless-service.yaml"
    echo "  kubectl apply -f 02-statefulset.yaml"
    exit 1
fi

# Wait for pods to be ready
echo "Waiting for all pods to be ready..."
kubectl wait --for=condition=ready pod -l app=web --timeout=120s

echo ""
echo "Step 1: Write unique data to each pod"
echo "--------------------------------------"
for i in 0 1 2; do
    echo "Writing to web-$i..."
    kubectl exec web-$i -- sh -c "echo '<h1>Hello from web-$i</h1><p>Created: $(date)</p>' > /usr/share/nginx/html/index.html"
done

echo ""
echo "Step 2: Verify data in each pod"
echo "--------------------------------"
for i in 0 1 2; do
    echo "Reading from web-$i:"
    kubectl exec web-$i -- cat /usr/share/nginx/html/index.html
    echo ""
done

echo ""
echo "Step 3: Delete pod web-1 (simulating failure)"
echo "----------------------------------------------"
kubectl delete pod web-1
echo "Pod deleted. Waiting for recreation..."
kubectl wait --for=condition=ready pod web-1 --timeout=60s

echo ""
echo "Step 4: Verify data persisted in recreated pod"
echo "-----------------------------------------------"
echo "Reading from web-1 after recreation:"
kubectl exec web-1 -- cat /usr/share/nginx/html/index.html

echo ""
echo "=== Test Complete ==="
echo ""
echo "Notice: The data in web-1 survived pod deletion!"
echo "This is because the PVC persists independently of the pod."
echo ""
echo "Check PVCs:"
kubectl get pvc -l app=web

echo ""
echo "Optional: Scale down to 1 and back to 3"
echo "  kubectl scale statefulset web --replicas=1"
echo "  kubectl get pvc  # PVCs still exist!"
echo "  kubectl scale statefulset web --replicas=3"
echo "  kubectl exec web-2 -- cat /usr/share/nginx/html/index.html  # Data preserved!"
