#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Verifying Deployment...${NC}"

# Check Namespace
echo -n "Checking Namespace... "
if kubectl get ns kube-lifecycle &> /dev/null; then
  echo -e "${GREEN}OK${NC}"
else
  echo -e "${RED}MISSING${NC}"
  echo "Please run: kubectl apply -f manifests/common/"
  exit 1
fi

# Check Deployments
deployments=("frontend-v1" "api-gateway-blue" "product-service" "order-service")
for deploy in "${deployments[@]}"; do
  echo -n "Checking Deployment $deploy... "
  if kubectl get deployment $deploy -n kube-lifecycle &> /dev/null; then
     AVAILABLE=$(kubectl get deployment $deploy -n kube-lifecycle -o jsonpath='{.status.availableReplicas}')
     if [[ -n "$AVAILABLE" && "$AVAILABLE" -gt 0 ]]; then
        echo -e "${GREEN}OK ($AVAILABLE ready)${NC}"
     else
        # It exists but might be 0 replicas or failing
        echo -e "${RED}NOT READY${NC}"
     fi
  else
     echo -e "${RED}MISSING${NC}"
  fi
done

# Check Services
services=("frontend" "api-gateway" "product-service" "order-service")
for svc in "${services[@]}"; do
  echo -n "Checking Service $svc... "
  if kubectl get svc $svc -n kube-lifecycle &> /dev/null; then
    echo -e "${GREEN}OK${NC}"
  else
    echo -e "${RED}MISSING${NC}"
  fi
done

echo
echo -e "${BLUE}Deployment Verification Complete.${NC}"
echo "Run the specific demo instructions from README.md to test Canary and Blue/Green scenarios."
