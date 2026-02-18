# Kubernetes Networking and Scheduling

> Pod scheduling with [[Node Affinity]], [[Taints and Tolerations]], [[PriorityClass]], [[Static Pods]], service types, and cluster setup with [[kubeadm]].
>
> Part of [[Container Networking]] · See also [[Kubernetes Storage]] and [[Deployment Strategies]]

---

## Kubernetes vs Docker Swarm

[[Kubernetes]] is the industry-standard orchestrator. Where [[Docker Swarm]] is simpler, [[Kubernetes]] offers:

| Feature | [[Docker Swarm]] | [[Kubernetes]] |
|---------|-----------------|----------------|
| Scheduling | Basic constraints | Rich affinity, taints, priorities |
| Storage | Volume drivers | PV/PVC/StorageClass/CSI |
| Auto-scaling | Manual / custom | Native HPA |
| Rolling updates | Basic | Configurable with rollback |
| Ecosystem | Small | Massive (Helm, operators, CRDs) |

---

## Setting Up a Cluster with [[kubeadm]] on [[AWS]]

Use [[Terraform]] to provision [[EC2]] instances and bootstrap [[Kubernetes]]:

```bash
# Configure credentials
echo 'access_key = "YOUR_KEY"' > terraform.tfvars
echo 'secret_key = "YOUR_SECRET"' >> terraform.tfvars

# Deploy the infrastructure
terraform init
terraform apply -var-file=terraform.tfvars

# SSH into the control plane
chmod 400 k8s-key
ssh -i k8s-key ubuntu@$(cat master_public_ip)

# Destroy when done
terraform destroy -var-file=terraform.tfvars
```

### Cluster layout

| Node | Instance Type | Labels | Taints |
|------|-------------|--------|--------|
| Control Plane | t3.medium | — | — |
| Worker 1 | t3.medium | `tier=frontend`, `storage=ssd` | `workload=frontend:NoSchedule` |
| Worker 2 | t3.medium | `tier=backend`, `storage=hdd` | `workload=backend:NoSchedule` |
| Worker 3 | t3.medium | (general purpose) | — |

---

## Pod Scheduling

[[Kubernetes]] gives fine-grained control over **where pods run**.

### Node Labels and nodeSelector

The simplest scheduler control — match labels exactly:

```bash
# Label nodes
kubectl label nodes worker-1 tier=frontend storage=ssd
kubectl label nodes worker-2 tier=backend storage=hdd
```

```yaml
# Pod runs ONLY on nodes with tier=backend
spec:
  nodeSelector:
    tier: backend
```

---

### [[Node Affinity]] — Advanced Rules

More powerful than nodeSelector — supports `required` (hard) and `preferred` (soft) rules:

```yaml
affinity:
  nodeAffinity:
    # MUST match — pod stays Pending if no node qualifies
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: tier
              operator: In
              values: ["backend"]
    # TRY to match — falls back to any valid node
    preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        preference:
          matchExpressions:
            - key: storage
              operator: In
              values: ["ssd"]
```

> [!important] `required` vs `preferred`
> - **required** → Pod stays `Pending` forever if no node matches
> - **preferred** → Scheduler *tries* but places elsewhere if needed

---

### Pod Anti-Affinity — Spreading Replicas

Force replicas onto **different nodes** for high availability:

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app: redis
        topologyKey: kubernetes.io/hostname
```

Each [[Redis]] replica runs on a different node. If you scale to more replicas than nodes, extras stay `Pending`.

---

### [[Taints and Tolerations]]

Nodes **repel** pods unless the pod explicitly tolerates the taint. Think of it as a bouncer at a door.

```bash
# Taint a node — only tolerating pods allowed
kubectl taint nodes worker-1 workload=frontend:NoSchedule
```

```yaml
# Pod that can get past the bouncer
tolerations:
  - key: "workload"
    operator: "Equal"
    value: "frontend"
    effect: "NoSchedule"
```

**Taint effects:**
| Effect | Behavior |
|--------|---------|
| `NoSchedule` | New pods won't be scheduled (existing stay) |
| `PreferNoSchedule` | Scheduler avoids but will place if necessary |
| `NoExecute` | Existing pods are evicted immediately |

---

### [[PriorityClass]] — Preemption

Higher-priority pods can **evict** lower-priority pods when resources are scarce:

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000
globalDefault: false
description: "For user-facing services"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: low-priority
value: 100
description: "For batch jobs — can be preempted"
```

```yaml
# Use in a pod
spec:
  priorityClassName: high-priority
```

---

## Service Types

| Type | Scope | Use Case |
|------|-------|----------|
| `ClusterIP` | Internal only | Service-to-service |
| `NodePort` | External via `<NodeIP>:<Port>` | Development / testing |
| `LoadBalancer` | Cloud provider LB | Production external access |
| `ExternalName` | DNS CNAME alias | Bridging to external services |

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30080
  selector:
    app: frontend
```

Traffic to `<AnyNodeIP>:30080` is distributed across matching pods by `kube-proxy`.

---

## [[Static Pods]]

Managed by the **kubelet** directly, not the API server:

```bash
# Create — place manifest on the node directly
sudo cp monitoring-agent.yaml /etc/kubernetes/manifests/

# CANNOT be deleted via kubectl — kubelet recreates immediately!
kubectl delete pod monitoring-agent-worker-1  # → Immediately comes back

# To actually remove — delete the file
sudo rm /etc/kubernetes/manifests/monitoring-agent.yaml
```

**Use cases:** Control plane components (etcd, kube-apiserver), node-level monitoring agents.

---

## Draining and Recovery

```bash
# Safely evacuate a node (for maintenance)
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data --force

# What happens:
# - Pods with strict nodeSelector for this node → Pending
# - Flexible pods → Rescheduled to other nodes
# - Static pods → Stay running (kubelet manages them)

# Bring the node back
kubectl uncordon worker-1
```

---

## Troubleshooting Scheduling

```bash
# Why is a pod Pending?
kubectl describe pod <pod-name>
# Check Events:
#   "0/3 nodes are available: 1 had taint, 2 didn't match selector"
#   "Insufficient cpu"

# Common fix: resource requests too high
# Change: cpu: "5000m" → cpu: "50m"

# Check node resources
kubectl describe node <node-name> | grep -A 5 "Allocated"

# Recent events
kubectl get events --sort-by=.lastTimestamp

# Shell into a running pod
kubectl exec -it <pod> -- sh

# Previous crash logs
kubectl logs <pod> --previous
```

---

## Next Steps

- For persistent data, see [[Kubernetes Storage]]
- For zero-downtime updates, see [[Deployment Strategies]]
- For monitoring and resilience, see [[Advanced Container Topics]]

---

#kubernetes #scheduling #node-affinity #taints #tolerations #container-networking #services
