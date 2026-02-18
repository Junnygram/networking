# Deployment Strategies

> [[Canary deployment]], [[Blue-Green deployment]], [[Rolling Update]]s, and [[Helm]] charts for zero-downtime [[Kubernetes]] updates.
>
> Part of [[Container Networking]] · See also [[Kubernetes Networking and Scheduling]]

---

## Overview

Updating a running application without downtime requires a strategy. [[Kubernetes]] supports three main patterns:

| Strategy | Risk | Rollback Speed | Resource Cost |
|----------|------|----------------|---------------|
| [[Canary deployment]] | Low (small traffic %) | Medium | Low |
| [[Blue-Green deployment]] | Medium | Instant | High (2x resources) |
| [[Rolling Update]] | Medium | Fast | Low |

---

## 🐤 Canary Deployment

Send a **small percentage of traffic** to the new version. Monitor, validate, then promote.

```
                  ┌─── V1 (3 replicas) ── ~75% traffic
  Service ────────┤
                  └─── V2 (1 replica)  ── ~25% traffic
```

### How it works

1. Keep V1 running with its current replicas
2. Deploy V2 as a **separate Deployment** with fewer replicas
3. Both Deployments share the **same label** matched by the Service
4. Traffic split is determined by the replica ratio

```yaml
# V1 Deployment (3 replicas)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-v1
spec:
  replicas: 3
  selector:
    matchLabels:
      app: frontend      # ← Service matches this
  template:
    metadata:
      labels:
        app: frontend
        version: v1
    spec:
      containers:
        - name: frontend
          image: myapp:1.0

---
# V2 Deployment (1 replica = ~25% traffic)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-v2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend      # ← Same label = same Service
  template:
    metadata:
      labels:
        app: frontend
        version: v2
    spec:
      containers:
        - name: frontend
          image: myapp:2.0

---
# Service routes to ALL pods with app=frontend
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  selector:
    app: frontend         # ← Matches both V1 and V2 pods
  ports:
    - port: 80
```

### Promote or rollback

```bash
# Monitor which version is responding
while true; do
  curl -s http://localhost:30080/ | grep "Version"
  sleep 0.5
done

# Promote V2
kubectl scale deployment frontend-v2 --replicas=3
kubectl scale deployment frontend-v1 --replicas=0

# Or rollback — just remove V2
kubectl delete deployment frontend-v2
```

---

## 🔵🟢 Blue-Green Deployment

Run both versions **simultaneously**. Switch traffic instantly by changing the Service selector.

### How it works

1. **Blue** (current) is running and serving all traffic
2. Deploy **Green** (new) alongside — no traffic yet
3. Validate Green is healthy
4. Patch the Service selector → **instant cutover**

```yaml
# Blue Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway-blue
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
      color: blue
  template:
    metadata:
      labels:
        app: api-gateway
        color: blue
    spec:
      containers:
        - name: api
          image: myapp:1.0

---
# Green Deployment
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway-green
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-gateway
      color: green
  template:
    metadata:
      labels:
        app: api-gateway
        color: green
    spec:
      containers:
        - name: api
          image: myapp:2.0

---
# Service — points to Blue initially
apiVersion: v1
kind: Service
metadata:
  name: api-gateway
spec:
  selector:
    app: api-gateway
    color: blue              # ← Change this to switch
  ports:
    - port: 80
```

### Switch and rollback

```bash
# Verify Green is healthy
kubectl rollout status deployment/api-gateway-green

# Instant switch to Green
kubectl patch service api-gateway -p '{"spec":{"selector":{"color":"green"}}}'

# Instant rollback to Blue
kubectl patch service api-gateway -p '{"spec":{"selector":{"color":"blue"}}}'

# Clean up old version once confident
kubectl delete deployment api-gateway-blue
```

---

## 🔄 Rolling Update

Gradually replace old pods with new ones. **Built into Kubernetes Deployments** — this is the default strategy.

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1   # At most 1 pod down during update
      maxSurge: 1          # At most 1 extra pod during update
```

### Execute and manage

```bash
# Trigger a rolling update
kubectl set image deployment/product-service \
  product-service=myregistry/product-service:v2

# Watch the rollout in real-time
kubectl rollout status deployment/product-service

# Rollback if something goes wrong
kubectl rollout undo deployment/product-service

# View rollout history
kubectl rollout history deployment/product-service
```

---

## [[Helm]] — Package Manager for [[Kubernetes]]

[[Helm]] packages Kubernetes manifests into reusable, parameterized **charts**:

### Chart structure

```
ecommerce-stack/
├── Chart.yaml           # Chart metadata
├── values.yaml          # Default configuration values
└── templates/
    ├── deployment.yaml  # Template using {{ .Values.xxx }}
    ├── service.yaml
    └── ingress.yaml
```

### Usage

```bash
# Install a release
helm install shop ./ecommerce-stack -n production --create-namespace

# Override values
helm install shop ./ecommerce-stack --set frontend.replicaCount=5

# Upgrade with new values or chart changes
helm upgrade shop ./ecommerce-stack -n production

# Rollback to previous release
helm rollback shop 1

# List releases
helm list -n production

# Uninstall
helm uninstall shop -n production
```

### Why Helm?

| Without Helm | With Helm |
|-------------|-----------|
| Manage dozens of YAML files | One `helm install` command |
| Hardcode environment-specific values | `values.yaml` per environment |
| Manual rollback by re-applying old files | `helm rollback` |
| No versioning of deployments | Full release history |

---

## Choosing a Strategy

| Question | Canary | Blue-Green | Rolling |
|----------|--------|------------|---------|
| Need to test with real traffic? | ✅ Best | ❌ | ❌ |
| Need instant rollback? | Medium | ✅ Best | Fast |
| Limited resources? | ✅ Low cost | ❌ 2x resources | ✅ Low cost |
| Simple setup? | Medium | Medium | ✅ Default |

---

## Next Steps

- For monitoring these deployments and testing resilience, see [[Advanced Container Topics]]
- For scheduling and node management, see [[Kubernetes Networking and Scheduling]]
- For stateful workload data, see [[Kubernetes Storage]]

---

#kubernetes #deployment #canary #blue-green #rolling-update #helm #container-networking
