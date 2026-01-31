# Group Assignment 1: Complete Application Lifecycle

## 📋 Scenario
We are deploying a microservices e-commerce application with distinct lifecycle strategies for each component:
- **Frontend**: Nginx serving static content (Canary Deployment)
- **API Gateway**: Nginx reverse proxy (Blue-Green Deployment)
- **Backend Services**: Product & Order services (Rolling Updates)

## 🚀 Deployment Instructions

### 1. Setup Environment
Open a [Killercoda Kubernetes Playground](https://killercoda.com/playgrounds/scenario/kubernetes) and run the following commands:

```bash
# Clone the repository
git clone https://github.com/Junnygram/networking.git
cd networking s
git checkout kube_lifecycle

# Go to the assignment directory
cd kube_lifecycle
```

### 2. Deploy Application
Apply the manifests in the following order:

```bash
# 1. Create Namespace and Common Resources (ConfigMaps, Secrets)
kubectl apply -f manifests/common/

# 2. Deploy Backend Services (Product, Order)
kubectl apply -f manifests/product-service/
kubectl apply -f manifests/order-service/

# 3. Deploy Frontend (Service, V1 Deployment, HPA)
# Note: This creates V1 (3 replicas) and V2 (1 replica) by default
kubectl apply -f manifests/frontend/

# 4. Deploy API Gateway (Service, Blue Deployment, HPA)
kubectl apply -f manifests/api-gateway/
```

### 3. Verify Deployment
Run the included verification script to ensure all components are healthy:

```bash
chmod +x tests/verify.sh
./tests/verify.sh
```

---

## 🎮 Demo Scenarios

### Scenario A: Canary Deployment (Frontend)
**Goal**: Validate the new V2 UI with a small percentage of users before a full rollout.

1.  **Observe Traffic Splitting**:
    The Frontend Service load balances across all pods. With 3 pods of V1 and 1 pod of V2, you will see a ~25% split.
    Run this loop to see the versions responding:
    ```bash
    # Note: Use the NodePort (likely 30000-32767) if External IP is pending
    # Check port with: kubectl get svc api-gateway -n kube-lifecycle
    PORT=$(kubectl get svc api-gateway -n kube-lifecycle -o jsonpath='{.spec.ports[0].nodePort}')
    
    while true; do 
      curl -s http://localhost:$PORT/ | grep "Version"
      sleep 0.5
    done
    ```
    *Output should show mostly "V1 (Stable)" and some "V2 (Canary)".*

2.  **Promote V2 (Full Rollout)**:
    If testing is successful, scale up V2 and remove V1.
    ```bash
    kubectl scale deployment frontend-v2 -n kube-lifecycle --replicas=3
    kubectl scale deployment frontend-v1 -n kube-lifecycle --replicas=0
    ```

### Scenario B: Blue-Green Deployment (API Gateway)
**Goal**: Instantly switch traffic from the old "Blue" version to the new "Green" version.

1.  **Deploy Green Version**:
    Start the new version alongside the old one. It takes no traffic yet.
    ```bash
    kubectl scale deployment api-gateway-green -n kube-lifecycle --replicas=2
    ```
    *Wait for readiness:* `kubectl rollout status deployment/api-gateway-green -n kube-lifecycle`

2.  **Switch Traffic (Cutover)**:
    Update the Service to point to the Green pods.
    ```bash
    kubectl patch service api-gateway -n kube-lifecycle -p '{"spec":{"selector":{"color":"green"}}}'
    ```

3.  **Verify**:
    Confirm the Service is now targeting Green.
    ```bash
    kubectl get svc api-gateway -n kube-lifecycle -o yaml | grep color
    ```

### Scenario C: Backend Rolling Update
**Goal**: Update the Product Service with zero downtime.

1.  **Trigger Update**:
    Simulate a new image release by updating an environment variable.
    ```bash
    kubectl set env deployment/product-service -n kube-lifecycle UPDATE_DATE=$(date)
    ```

2.  **Watch Rollout**:
    Kubernetes will create new pods and terminate old ones one by one.
    ```bash
    kubectl rollout status deployment/product-service -n kube-lifecycle
    ```

---

## 📦 Helm Chart
Alternatively, you can deploy the entire stack using Helm.

```bash
helm install shop ./helm/ecommerce-stack -n kube-lifecycle --create-namespace
```
