# Kubernetes Storage

> [[PersistentVolume]]s, [[PersistentVolumeClaim]]s, [[StorageClass]]es, [[StatefulSet]]s, access modes, and production storage with [[Rook]]-[[Ceph]].
>
> Part of [[Container Networking]] · See also [[Kubernetes Networking and Scheduling]]

---

## Why Storage Matters

Containers are **ephemeral** — when they restart, everything inside is lost. For databases, logs, and state, you need **persistent storage** that survives container restarts, rescheduling, and even node failures.

[[Kubernetes]] solves this by decoupling **what storage a pod needs** from **how that storage is provided**.

---

## The Storage Triangle

```
        ┌─────────────┐
        │     POD      │
        │ volumeMounts │
        └──────┬───────┘
               │ references
        ┌──────┴──────┐
        │     PVC      │  ← Developer creates ("I need 1Gi of RWO storage")
        └──────┬───────┘
               │ binds to
        ┌──────┴──────┐
        │      PV      │  ← Admin creates or dynamic provisioner auto-creates
        └──────────────┘
```

| Component | Who Creates It | Purpose | Analogy |
|-----------|---------------|---------|---------|
| **[[PersistentVolume]] (PV)** | Admin or provisioner | The actual storage | The hard drive |
| **[[PersistentVolumeClaim]] (PVC)** | Developer | Request for storage | An order form |
| **[[StorageClass]]** | Admin | Template for dynamic provisioning | Pre-approved vendor list |

---

## Static Provisioning — Manual Setup

Admin creates a PV, developer claims it with a PVC:

```yaml
# 1. Admin creates PV
apiVersion: v1
kind: PersistentVolume
metadata:
  name: my-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /data/my-volume
  persistentVolumeReclaimPolicy: Retain
---
# 2. Developer creates PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
# 3. Pod uses the PVC
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
    - name: app
      image: nginx
      volumeMounts:
        - mountPath: /data
          name: storage
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: my-pvc
```

### Testing persistence

```bash
kubectl apply -f pv.yaml -f pvc.yaml -f pod.yaml

# Write data
kubectl exec my-pod -- sh -c "echo 'Hello!' > /data/test.txt"

# Delete the pod
kubectl delete pod my-pod

# Recreate it — same PVC reattaches
kubectl apply -f pod.yaml
kubectl exec my-pod -- cat /data/test.txt  # → "Hello!" ✅
```

Data survives pod deletion because the PVC holds the binding to the PV.

---

## Dynamic Provisioning — Automatic

Instead of pre-creating PVs, define a [[StorageClass]] and let the provisioner create PVs on demand:

```yaml
# StorageClass — the template
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-storage
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
```

Now just create a PVC — the PV is created automatically:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: auto-pvc
spec:
  storageClassName: fast-storage
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

> [!tip]
> `WaitForFirstConsumer` delays PV creation until a pod actually needs it — important for topology-aware scheduling.

---

## Access Modes

| Mode | Short | Description | Use Case |
|------|-------|-------------|----------|
| `ReadWriteOnce` | RWO | One node, read-write | Databases ([[PostgreSQL]], [[Redis]]) |
| `ReadOnlyMany` | ROX | Many nodes, read-only | Shared configs, static assets |
| `ReadWriteMany` | RWX | Many nodes, read-write | Shared uploads (needs NFS/CephFS) |
| `ReadWriteOncePod` | RWOP | Single pod, read-write | Strict single-writer guarantee |

> [!important]
> Most cloud block storage (EBS, GCE PD) only supports **RWO**. For RWX, you need a distributed filesystem like [[Ceph]]FS or NFS.

---

## Reclaim Policies

| Policy | On PVC Deletion | When to Use |
|--------|----------------|-------------|
| **Retain** | PV and data preserved — manual cleanup needed | Production data |
| **Delete** | PV and backing storage deleted automatically | Development/ephemeral |

---

## [[StatefulSet]]s — Stateful Workloads

For databases and stateful apps, [[StatefulSet]]s provide what Deployments can't:

| Feature | Deployment | StatefulSet |
|---------|-----------|-------------|
| Hostnames | Random (`web-xyz123`) | Stable (`web-0`, `web-1`, `web-2`) |
| Storage | Shared PVC | **Individual PVC per replica** |
| Startup | All at once | Ordered (0 → 1 → 2) |
| Scale down | Random pod killed | Highest index first (2 → 1 → 0) |
| PVC cleanup | Deleted with pod | **Retained** for reattachment |

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: web
spec:
  serviceName: web
  replicas: 3
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: nginx
          image: nginx
          volumeMounts:
            - name: data
              mountPath: /usr/share/nginx/html
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

Each pod gets its own PVC: `data-web-0`, `data-web-1`, `data-web-2`. Scale down retains PVCs; scale up reattaches them.

---

## Production Storage: [[Rook]]-[[Ceph]]

For production clusters needing distributed, resilient storage inside the cluster:

| Type | Protocol | Access | Use Case |
|------|----------|--------|----------|
| **Block (RBD)** | RADOS Block Device | RWO | Databases |
| **Filesystem (CephFS)** | POSIX filesystem | RWX | Shared data across pods |
| **Object (RGW)** | S3-compatible API | HTTP | Backups, media uploads |

```bash
# Install Rook operator
kubectl apply -f rook-operator.yaml

# Create a CephCluster
kubectl apply -f ceph-cluster.yaml

# Create StorageClasses for block and filesystem
kubectl apply -f ceph-block-sc.yaml
kubectl apply -f ceph-filesystem-sc.yaml

# Now PVCs using these StorageClasses get Ceph-backed storage
```

---

## Storage Troubleshooting

| Issue | Cause | Diagnosis |
|-------|-------|-----------|
| PVC stuck in `Pending` | No StorageClass, no PV, `WaitForFirstConsumer` | `kubectl describe pvc <name>` |
| Pod stuck in `ContainerCreating` | Volume mount failure | `kubectl describe pod <name>` |
| Data missing after restart | PVC deleted or wrong reclaim policy | `kubectl get pv` |
| Can't write to volume | Wrong access mode or permissions | Check mode + container user |

### Best practices

- Always use `WaitForFirstConsumer` for topology-aware scheduling
- Use `Retain` for production data — prevent accidental loss
- Monitor storage usage with [[Prometheus]]
- Back up with [[Velero]] for disaster recovery
- Test persistence by deleting and recreating pods

---

## Next Steps

- For zero-downtime updates, see [[Deployment Strategies]]
- For scheduling pods to specific nodes, see [[Kubernetes Networking and Scheduling]]
- For monitoring and resilience, see [[Advanced Container Topics]]

---

#kubernetes #storage #persistent-volumes #statefulsets #ceph #container-networking
