#!/bin/bash
# DevOps Utility Script for ShopMicro
# Automates environment health validation and evidence collection.

set -e

NAMESPACE="shopmicro"
# Use absolute path resolving from the script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
EVIDENCE_DIR="${SCRIPT_DIR}/../evidence"

mkdir -p "$EVIDENCE_DIR"

echo "=================================="
echo " ShopMicro DevOps Utility"
echo "=================================="

echo "[1/4] Checking Pod Status..."
kubectl get pods -n "$NAMESPACE" -o wide > "$EVIDENCE_DIR/pod_status.txt"
if grep -i "CrashLoopBackOff\|Error" "$EVIDENCE_DIR/pod_status.txt"; then
  echo "❌ Some pods are not in a healthy state (CrashLoopBackOff or Error)."
else
  echo "✅ All pods appear healthy."
fi

echo "[2/4] Verifying Ingress..."
kubectl get ingress -n "$NAMESPACE" > "$EVIDENCE_DIR/ingress_status.txt"
echo "✅ Ingress status collected."

echo "[3/4] Collecting HPA status..."
kubectl get hpa -n "$NAMESPACE" > "$EVIDENCE_DIR/hpa_status.txt" 
echo "✅ HPA status collected."

echo "[4/4] Validating Backend API (Internal DNS)..."
# We can spin up a temporary curl pod to test the backend API internally
if kubectl run curl-test -n "$NAMESPACE" --image=curlimages/curl --restart=Never --rm -i -- curl -s http://backend:8080/health > /dev/null 2>&1; then
    echo "✅ Backend internal API is reachable."
else
    echo "⚠️ Backend internal API check failed or curl pod could not be scheduled."
fi

echo "=================================="
echo "Health validation complete."
echo "Evidence collected in $EVIDENCE_DIR/"
echo "=================================="
