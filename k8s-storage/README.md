# Kubernetes Storage Deep Dive - Hands-On Lab

## Overview

This lab provides comprehensive coverage of Kubernetes persistent storage, from fundamental concepts to production-grade distributed storage with Rook-Ceph. You'll learn how storage flows through the Kubernetes ecosystem and gain practical experience with different storage patterns.

**What you'll learn:**
- How Persistent Volumes (PV), Persistent Volume Claims (PVC), and StorageClasses work together
- Static vs Dynamic provisioning patterns
- Access modes and their real-world implications
- Volume lifecycle management (retention, reclaim policies)
- StatefulSet storage patterns
- Production storage with Rook-Ceph (block, filesystem, object storage)
- Storage troubleshooting techniques

---

## Prerequisites

- Docker installed and running
- **One of these local Kubernetes tools:**
  - KinD (`brew install kind` or `go install sigs.k8s.io/kind@latest`)
  - k3d (`brew install k3d` or `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash`) - **Recommended**
- kubectl installed
- Basic understanding of Kubernetes pods and deployments

### KinD vs k3d

| Feature | KinD | k3d |
|---------|------|-----|
| Default StorageClass | standard (local-path) | local-path |
| Startup Speed | Slower | Faster |
| Resource Usage | Higher | Lower |
| Built-in Provisioner | Yes | Yes |
| Best For | Full K8s compatibility | Quick testing |

**Recommendation:** Use **k3d** for these storage labs - it's faster and has built-in storage that works out of the box.

---

## Architecture

### Kubernetes Storage Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Storage Architecture                             │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│   ┌──────────────┐    requests     ┌──────────────┐    binds to         │
│   │     Pod      │ ──────────────► │     PVC      │ ──────────────►     │
│   │              │                 │              │                      │
│   │  volumeMount │                 │ storageClass │     ┌──────────┐    │
│   └──────────────┘                 │ accessModes  │     │    PV    │    │
│                                    │ resources    │     │          │    │
│                                    └──────────────┘     │ capacity │    │
│                                           │             │ hostPath │    │
│                                           │             │ nfs      │    │
│                                           ▼             │ csi      │    │
│                                    ┌──────────────┐     └──────────┘    │
│                                    │ StorageClass │          ▲          │
│                                    │              │          │          │
│                                    │ provisioner  │──────────┘          │
│                                    │ parameters   │   provisions        │
│                                    │ reclaimPolicy│   (dynamic)         │
│                                    └──────────────┘                     │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Access Modes

| Mode | Abbreviation | Description |
|------|--------------|-------------|
| ReadWriteOnce | RWO | Single node can mount read-write |
| ReadOnlyMany | ROX | Multiple nodes can mount read-only |
| ReadWriteMany | RWX | Multiple nodes can mount read-write |
| ReadWriteOncePod | RWOP | Single pod can mount read-write (K8s 1.22+) |

### Reclaim Policies

| Policy | Behavior |
|--------|----------|
| Retain | PV preserved after PVC deletion (manual cleanup) |
| Delete | PV and underlying storage deleted with PVC |
| Recycle | (Deprecated) Basic scrub and reuse |

---

## Lab Structure

```
k8s-storage/
├── README.md                           # This file
├── 01-setup-cluster.sh                 # Create KinD cluster with storage
├── 01-setup-cluster-k3d.sh             # Create k3d cluster (recommended)
├── k3d-storage-guide.md                # k3d-specific storage guide
├── 02-fundamentals/                    # Core PV/PVC concepts
│   ├── 01-static-pv.yaml              # Manual PV creation
│   ├── 02-pvc-binding.yaml            # PVC that binds to PV
│   ├── 03-pod-with-volume.yaml        # Pod consuming PVC
│   └── 04-explore-binding.sh          # Interactive exploration script
├── 03-dynamic-provisioning/            # StorageClass patterns
│   ├── 01-storage-class.yaml          # Custom StorageClass
│   ├── 02-dynamic-pvc.yaml            # PVC with dynamic provisioning
│   └── 03-reclaim-policies.yaml       # Demonstrate retention behaviors
├── 04-statefulsets/                    # Stateful application storage
│   ├── 01-headless-service.yaml       # Required for StatefulSet
│   ├── 02-statefulset.yaml            # StatefulSet with volumeClaimTemplates
│   └── 03-test-persistence.sh         # Verify data survives restarts
├── 05-access-modes/                    # RWO vs RWX patterns
│   ├── 01-rwo-demo.yaml               # ReadWriteOnce example
│   ├── 02-rwx-demo.yaml               # ReadWriteMany with NFS
│   └── 03-multi-pod-conflict.yaml     # Demonstrate RWO limitations
├── 06-rook-ceph/                       # Production distributed storage
│   ├── README.md                       # Rook-Ceph specific guide
│   ├── k3d-guide.md                   # k3d-specific Rook-Ceph setup
│   ├── setup-k3d-rook.sh              # Automated k3d + Rook setup
│   ├── cluster-k3d-pvc.yaml           # Ceph cluster for k3d (PVC-backed)
│   ├── 01-prerequisites.md            # Hardware requirements (VMs)
│   ├── 02-install-operator.sh         # Deploy Rook operator
│   ├── 03-cluster.yaml                # CephCluster CR (production)
│   ├── 04-block-storage/              # RBD (block) examples
│   ├── 05-filesystem-storage/         # CephFS (shared) examples
│   └── 06-object-storage/             # RGW (S3-compatible) examples
├── 07-troubleshooting/                 # Common issues and fixes
│   └── README.md                       # Troubleshooting guide
└── 08-cleanup.sh                       # Tear down everything
```

---

## Step-by-Step Guide

### Step 1: Create Cluster

Choose **one** of the following options:

#### Option A: k3d (Recommended)

```bash
cd k8s-storage
./01-setup-cluster-k3d.sh
```

This creates a k3d cluster with:
- 1 server node + 3 agent nodes
- Built-in `local-path` StorageClass (default)
- Host storage mapped to `~/k3d-storage/storage-lab`

#### Option B: KinD

```bash
cd k8s-storage
./01-setup-cluster.sh
```

This creates a KinD cluster with:
- 1 control plane + 3 worker nodes
- `standard` StorageClass for dynamic provisioning

#### Verify the Cluster

```bash
kubectl get nodes
kubectl get storageclass
```

You should see a default StorageClass (`local-path` for k3d, `standard` for KinD).

---

### Step 2: Understanding Static Provisioning

Static provisioning means an administrator manually creates PVs before pods can use them.

**Create a Persistent Volume:**

```bash
kubectl apply -f 02-fundamentals/01-static-pv.yaml
```

Examine the PV:

```bash
kubectl get pv
kubectl describe pv static-pv-demo
```

Notice the status is `Available` - no PVC has claimed it yet.

**Create a PVC to bind to the PV:**

```bash
kubectl apply -f 02-fundamentals/02-pvc-binding.yaml
```

Check binding status:

```bash
kubectl get pv,pvc
```

The PV status changes to `Bound` and shows which PVC claimed it.

**Deploy a pod using the PVC:**

```bash
kubectl apply -f 02-fundamentals/03-pod-with-volume.yaml
```

Test data persistence:

```bash
# Write data
kubectl exec static-pod-demo -- sh -c "echo 'Hello from Kubernetes storage!' > /data/test.txt"

# Read it back
kubectl exec static-pod-demo -- cat /data/test.txt

# Delete the pod
kubectl delete pod static-pod-demo

# Recreate and verify data persisted
kubectl apply -f 02-fundamentals/03-pod-with-volume.yaml
kubectl exec static-pod-demo -- cat /data/test.txt
```

---

### Step 3: Dynamic Provisioning with StorageClasses

Dynamic provisioning automatically creates PVs when PVCs are created.

**Examine the default StorageClass:**

```bash
kubectl get storageclass local-path -o yaml
```

Key fields:
- `provisioner`: Which CSI driver creates volumes
- `reclaimPolicy`: What happens when PVC is deleted
- `volumeBindingMode`: When to provision (Immediate vs WaitForFirstConsumer)

**Create a PVC with dynamic provisioning:**

```bash
kubectl apply -f 03-dynamic-provisioning/02-dynamic-pvc.yaml
```

Check the PVC status:

```bash
kubectl get pvc dynamic-pvc-demo

# Status will be Pending until a pod uses it (WaitForFirstConsumer)
```

Create a pod to trigger provisioning:

```bash
kubectl run dynamic-test --image=busybox:1.36 \
  --overrides='{"spec":{"containers":[{"name":"dynamic-test","image":"busybox:1.36","command":["sleep","infinity"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"dynamic-pvc-demo"}}]}}'
```

Now watch the PV get created automatically:

```bash
kubectl get pv,pvc
```

**Understand reclaim policies:**

```bash
# First create the custom StorageClasses
kubectl apply -f 03-dynamic-provisioning/01-storage-class.yaml

# Create PVCs with different reclaim policies
kubectl apply -f 03-dynamic-provisioning/03-reclaim-policies.yaml

# Note the PV name for the delete-policy PVC
kubectl get pvc delete-policy-pvc -o jsonpath='{.spec.volumeName}'

# Delete the PVC
kubectl delete pvc delete-policy-pvc

# The PV is automatically deleted!
kubectl get pv

# Compare with retain-policy-pvc - its PV will remain with status 'Released'
```

---

### Step 4: StatefulSet Storage Patterns

StatefulSets provide stable, unique network identities and persistent storage for pods.

**Deploy a StatefulSet:**

```bash
kubectl apply -f 04-statefulsets/01-headless-service.yaml
kubectl apply -f 04-statefulsets/02-statefulset.yaml
```

Watch pods come up in order:

```bash
kubectl get pods -w -l app=web
```

Notice each pod gets its own PVC:

```bash
kubectl get pvc
```

**Test persistence per pod:**

```bash
# Write unique data to each pod
for i in 0 1 2; do
  kubectl exec web-$i -- sh -c "echo 'I am web-$i' > /data/identity.txt"
done

# Delete a pod
kubectl delete pod web-1

# Wait for it to restart, then verify data persisted
kubectl exec web-1 -- cat /data/identity.txt
```

**Scale the StatefulSet:**

```bash
# Scale up - new PVCs created
kubectl scale statefulset web --replicas=5

# Scale down - PVCs are retained!
kubectl scale statefulset web --replicas=3

# Check PVCs still exist
kubectl get pvc
```

---

### Step 5: Access Modes in Practice

**RWO (ReadWriteOnce) - Single Node Access:**

```bash
kubectl apply -f 05-access-modes/01-rwo-demo.yaml
```

Try scheduling pods on different nodes:

```bash
# This will show the limitation - only one node can mount
kubectl apply -f 05-access-modes/03-multi-pod-conflict.yaml

# Check pod status - some may be stuck in Pending
kubectl get pods -l demo=rwo-conflict
kubectl describe pod <pending-pod-name>
```

**RWX (ReadWriteMany) - Multi-Node Access:**

For RWX, you need a storage backend that supports it (NFS, CephFS, etc.). With local-path, we can simulate:

```bash
kubectl apply -f 05-access-modes/02-rwx-demo.yaml
```

---

### Step 6: Exploring Rook-Ceph (Advanced)

Rook-Ceph provides production-grade distributed storage.

#### Quick Start with k3d (PVC-backed OSDs)

For learning purposes, you can run Rook-Ceph on k3d using PVC-backed storage:

```bash
cd 06-rook-ceph
./setup-k3d-rook.sh
```

This creates a Ceph cluster using the `local-path` StorageClass to back the OSDs. See `k3d-guide.md` for details.

#### Production Setup (Real Hardware)

For production-grade testing, Rook-Ceph requires real storage (raw disks):

```bash
cd 06-rook-ceph
cat README.md          # General overview
cat 01-prerequisites.md # VM/hardware setup
```

**Options for real storage:**
- VMs with attached disks (Vagrant)
- Cloud instances with block storage (AWS EBS, GCP PD)
- Bare-metal servers with spare disks

#### Storage Types Available

The `06-rook-ceph/` directory contains examples for:
- **Block storage (RBD)** - single-pod attached storage (databases)
- **Shared filesystem (CephFS)** - multi-pod read-write (shared data)
- **Object storage (RGW)** - S3-compatible API (backups, media)

---

## Key Concepts Summary

### PV vs PVC vs StorageClass

| Component | Created By | Purpose |
|-----------|------------|---------|
| PV | Admin or Provisioner | Represents actual storage |
| PVC | Developer | Request for storage |
| StorageClass | Admin | Template for dynamic PV creation |

### When to Use What

| Use Case | Solution |
|----------|----------|
| Single pod needs persistent data | RWO PVC |
| Multiple pods share read-only data | ROX PVC |
| Multiple pods share read-write data | RWX PVC (needs CephFS/NFS) |
| Database with replicas | StatefulSet + RWO |
| Simple file serving | Deployment + RWX |

### Volume Binding Modes

| Mode | When PV is Provisioned | Use Case |
|------|------------------------|----------|
| Immediate | When PVC is created | Pre-provisioned storage |
| WaitForFirstConsumer | When pod is scheduled | Topology-aware provisioning |

---

## Exercises

### Exercise 1: Database Deployment

Deploy a PostgreSQL database with persistent storage:

1. Create a PVC requesting 5Gi
2. Deploy PostgreSQL using the PVC
3. Create a database and insert data
4. Delete the pod and verify data persists
5. Bonus: Set up a CronJob for backups

### Exercise 2: Multi-Replica Web App

Deploy an application where multiple pods share storage:

1. Research what storage backends support RWX
2. Deploy an NFS server in the cluster (or use CephFS)
3. Create an RWX PVC
4. Deploy 3 replicas sharing the storage
5. Test that writes from one pod are visible in others

### Exercise 3: StorageClass Comparison

Create and compare different StorageClasses:

1. Create StorageClass with `reclaimPolicy: Retain`
2. Create StorageClass with `reclaimPolicy: Delete`
3. Create PVCs using each class
4. Delete PVCs and observe the difference
5. Manually clean up retained PVs

### Exercise 4: Volume Expansion

Grow a volume without data loss:

1. Create a StorageClass with `allowVolumeExpansion: true`
2. Create a 1Gi PVC
3. Deploy a pod and write data
4. Expand the PVC to 2Gi
5. Verify the pod sees the expanded storage

---

## Troubleshooting

### PVC Stuck in Pending

```bash
kubectl describe pvc <pvc-name>
```

Common causes:
- No matching PV (static provisioning)
- StorageClass doesn't exist
- Insufficient resources
- `WaitForFirstConsumer` waiting for pod

### Pod Stuck in ContainerCreating

```bash
kubectl describe pod <pod-name>
```

Look for volume-related events:
- "Unable to attach or mount volumes"
- "FailedAttachVolume"

### Data Corruption

For debugging without affecting the pod:

```bash
# Clone the PVC (requires VolumeSnapshot support)
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: debug-snapshot
spec:
  source:
    persistentVolumeClaimName: problem-pvc
EOF
```

---

## Cleanup

```bash
./08-cleanup.sh
```

This removes all resources and the cluster (supports both k3d and KinD).

---

## References

- [Kubernetes Persistent Volumes Documentation](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [StorageClass Documentation](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [StatefulSets Documentation](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Rook-Ceph Documentation](https://rook.io/docs/rook/latest-release/)
- [CSI Specification](https://github.com/container-storage-interface/spec)

---

## Next Section

After completing this lab, explore:
- **Section 9: Troubleshooting** - Debug storage issues in production
- **Rook-Ceph Deep Dive** - Production distributed storage (requires proper hardware)
