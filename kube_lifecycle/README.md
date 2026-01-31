# Group Assignment 1: Complete Application Lifecycle

## 📋 Scenario
We are deploying a microservices e-commerce application with:
- **Frontend**: Nginx serving static content (Canary Deployment)
- **API Gateway**: Nginx reverse proxy (Blue-Green Deployment)
- **Backend**: Product & Order services (Rolling Updates)

## 🚀 Killercoda Deployment Instructions

### 1. Setup Environment
Open a [Killercoda Kubernetes Playground](https://killercoda.com/playgrounds/scenario/kubernetes) and run the following commands:

```bash
# Clone the repository
git clone https://github.com/junioroyewunmi/networking.git
cd networking
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
**Goal**: Test a new UI (V2) with a small subset of users (traffic split).

1. **Deploy V2 Canary**:
   ```bash
   # Scale up the V2 deployment (currently set to 1 replica)
   kubectl scale deployment frontend-v2 -n kube-lifecycle --replicas=1
   ```
2. **Observe Traffic**:
   Access the Frontend Service IP. You will see mostly "Version: V1 (Stable)" (Purple) and occasionally "Version: V2 (Canary)" (Orange).
3. **Promote V2**:
   ```bash
   kubectl scale deployment frontend-v2 -n kube-lifecycle --replicas=3
   kubectl scale deployment frontend-v1 -n kube-lifecycle --replicas=0
   ```

### Scenario B: Blue-Green Deployment (API Gateway)
**Goal**: Switch traffic instantly from Blue (Active) to Green (Idle).

1. **Deploy Green Version**:
   ```bash
   kubectl scale deployment api-gateway-green -n kube-lifecycle --replicas=2
   ```
2. **Wait for Readiness**:
   ```bash
   kubectl rollout status deployment/api-gateway-green -n kube-lifecycle
   ```
3. **Switch Traffic**:
   Edit the Service to point to Green:
   ```bash
   kubectl patch service api-gateway -n kube-lifecycle -p '{"spec":{"selector":{"color":"green"}}}'
   ```
4. **Verify**:
   Traffic now flows to the Green deployment.

### Scenario C: Backend Rolling Update
**Goal**: Update the Product Service without downtime.

1. **Trigger Update**:
   ```bash
   # Update the image (or an env var to trigger restart if image is same)
   kubectl set env deployment/product-service -n kube-lifecycle UPDATE_DATE=$(date)
   ```
2. **Watch Rollout**:
   ```bash
   kubectl rollout status deployment/product-service -n kube-lifecycle
   ```
   You will see old pods terminating only after new pods are ready.

---

## 📦 Helm Chart
A Helm chart is also provided for deploying the entire stack as a single package.

```bash
helm install shop ./helm/ecommerce-stack -n kube-lifecycle
```
