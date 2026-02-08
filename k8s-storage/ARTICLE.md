# Kubernetes Storage Deep Dive: A Complete Hands-On Guide for DevOps Engineers

![Kubernetes Storage](https://kubernetes.io/images/kubernetes-horizontal-color.png)

> 🚀 **Clone the repo and follow along**: This is a 100% hands-on tutorial. By the end, you'll have mastered Kubernetes persistent storage from fundamentals to production-ready patterns.

## 📋 Table of Contents

1. [Introduction](#introduction)
2. [What You'll Learn](#what-youll-learn)
3. [Prerequisites](#prerequisites)
4. [Setting Up Your Lab Environment](#setting-up-your-lab-environment)
5. [Understanding Kubernetes Storage Architecture](#understanding-kubernetes-storage-architecture)
6. [Lab 1: Static Provisioning Fundamentals](#lab-1-static-provisioning-fundamentals)
7. [Lab 2: Dynamic Provisioning with StorageClasses](#lab-2-dynamic-provisioning-with-storageclasses)
8. [Lab 3: StatefulSet Storage Patterns](#lab-3-statefulset-storage-patterns)
9. [Lab 4: Access Modes Deep Dive](#lab-4-access-modes-deep-dive)
10. [Lab 5: Production Storage with Rook-Ceph (Advanced)](#lab-5-production-storage-with-rook-ceph-advanced)
11. [Troubleshooting Common Issues](#troubleshooting-common-issues)
12. [Key Takeaways & Next Steps](#key-takeaways--next-steps)

---

## Introduction

One of the most critical aspects of running stateful applications in Kubernetes is **persistent storage**. Unlike ephemeral containers that lose all data upon restart, persistent storage ensures your databases, file uploads, and application state survive pod restarts, node failures, and cluster migrations.

In this comprehensive hands-on guide, we'll explore every aspect of Kubernetes storage:

- How PersistentVolumes (PV), PersistentVolumeClaims (PVC), and StorageClasses work together
- The difference between static and dynamic provisioning
- Real-world patterns for StatefulSets
- Access modes and when to use each
- Production-grade distributed storage with Rook-Ceph

**The best way to learn is by doing.** Clone the repository and follow along!

---

## What You'll Learn

By the end of this tutorial, you'll be able to:

✅ Create and manage Persistent Volumes and Persistent Volume Claims  
✅ Implement dynamic provisioning with StorageClasses  
✅ Deploy stateful applications with proper storage patterns  
✅ Understand access modes (RWO, ROX, RWX, RWOP) and their use cases  
✅ Troubleshoot common storage issues  
✅ Set up production-grade distributed storage with Rook-Ceph  

---

## Prerequisites

Before we begin, ensure you have:

- **Docker** installed and running
- **kubectl** installed
- **k3d** or **KinD** (we'll install k3d if needed)
- Basic understanding of Kubernetes pods and deployments

### Clone the Repository

```bash
git clone https://github.com/YOUR_USERNAME/k8s-storage.git
cd k8s-storage
```

---

## Setting Up Your Lab Environment

We'll use **k3d** for this lab because it's lightweight, fast, and comes with built-in storage provisioning.

### Step 1: Run the Setup Script

```bash
./01-setup-cluster-k3d.sh
```

This script will:
1. Install k3d if not present
2. Create a 4-node cluster (1 server + 3 agents)
3. Configure the `local-path` StorageClass as default
4. Set up host storage mapping for persistence

### Step 2: Verify Your Cluster

```bash
# Check nodes are ready
kubectl get nodes

# Expected output:
# NAME                       STATUS   ROLES                  AGE   VERSION
# k3d-storage-lab-server-0   Ready    control-plane,master   1m    v1.28.4+k3s1
# k3d-storage-lab-agent-0    Ready    <none>                 1m    v1.28.4+k3s1
# k3d-storage-lab-agent-1    Ready    <none>                 1m    v1.28.4+k3s1
# k3d-storage-lab-agent-2    Ready    <none>                 1m    v1.28.4+k3s1

# Check StorageClass
kubectl get storageclass

# Expected output:
# NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
# local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false
```

🎉 **Checkpoint**: You now have a fully functional Kubernetes cluster ready for storage experiments!

---

## Understanding Kubernetes Storage Architecture

Before we dive into hands-on labs, let's understand how storage works in Kubernetes.

### The Storage Triangle

```
                    ┌─────────────────────┐
                    │        POD          │
                    │                     │
                    │   volumeMounts:     │
                    │     - /data         │
                    └──────────┬──────────┘
                               │ references
                               ▼
                    ┌─────────────────────┐
                    │        PVC          │
                    │                     │
                    │  "I need 1Gi of     │
                    │   RWO storage"      │
                    └──────────┬──────────┘
                               │ binds to
                               ▼
                    ┌─────────────────────┐
                    │        PV           │
                    │                     │
                    │  "I provide 1Gi     │
                    │   on this node"     │
                    └─────────────────────┘
```

### Key Components Explained

| Component | Created By | Purpose | Analogy |
|-----------|------------|---------|---------|
| **PersistentVolume (PV)** | Admin or Provisioner | Actual storage resource | The hard drive |
| **PersistentVolumeClaim (PVC)** | Developer | Request for storage | Order form for storage |
| **StorageClass** | Admin | Template for dynamic PVs | Pre-approved vendor list |

### Access Modes

| Mode | Short Name | Description | Use Case |
|------|------------|-------------|----------|
| ReadWriteOnce | RWO | Single node read-write | Databases, single-instance apps |
| ReadOnlyMany | ROX | Multiple nodes read-only | Shared configs, static assets |
| ReadWriteMany | RWX | Multiple nodes read-write | Shared file uploads, CMS |
| ReadWriteOncePod | RWOP | Single pod read-write | Strict single-writer apps |

### Reclaim Policies

| Policy | What Happens When PVC is Deleted | Use Case |
|--------|----------------------------------|----------|
| **Retain** | PV and data preserved | Production data, manual backup |
| **Delete** | PV and data deleted | Development, temporary storage |
| **Recycle** | (Deprecated) Basic `rm -rf` | Don't use |

---

## Lab 1: Static Provisioning Fundamentals

Static provisioning is when an administrator manually creates PVs before applications can use them. This is common in environments with pre-allocated storage.

### What We'll Do

1. Create a PersistentVolume manually
2. Create a PersistentVolumeClaim that binds to it
3. Deploy a pod that uses the storage
4. Prove data persists across pod restarts

### Step 1: Create the Persistent Volume

```bash
cat 02-fundamentals/01-static-pv.yaml
```

Let's understand what we're creating:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: static-pv-demo
  labels:
    type: local
spec:
  capacity:
    storage: 1Gi                        # How much storage
  accessModes:
    - ReadWriteOnce                     # Single node can mount read-write
  persistentVolumeReclaimPolicy: Retain # Keep data after PVC deletion
  storageClassName: manual              # Must match PVC
  hostPath:
    path: /mnt/data/static-demo         # Directory on the node
    type: DirectoryOrCreate
```

Apply it:

```bash
kubectl apply -f 02-fundamentals/01-static-pv.yaml
```

Check the PV status:

```bash
kubectl get pv

# Output:
# NAME               CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   AGE
# static-pv-demo     1Gi        RWO            Retain           Available           manual         5s
# static-pv-demo-2   2Gi        RWO            Retain           Available           manual         5s
```

Notice the status is **Available** — no one has claimed it yet!

### Step 2: Create a Persistent Volume Claim

```bash
cat 02-fundamentals/02-pvc-binding.yaml
```

The PVC requests storage:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: static-pvc-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi          # We need 500Mi
  storageClassName: manual    # Must match PV's storageClassName
```

Apply it:

```bash
kubectl apply -f 02-fundamentals/02-pvc-binding.yaml
```

Check the binding:

```bash
kubectl get pv,pvc

# Output:
# NAME                              CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                     STORAGECLASS
# persistentvolume/static-pv-demo   1Gi        RWO            Retain           Bound    default/static-pvc-demo   manual

# NAME                                  STATUS   VOLUME           CAPACITY   ACCESS MODES   STORAGECLASS
# persistentvolumeclaim/static-pvc-demo Bound    static-pv-demo   1Gi        RWO            manual
```

🔍 **Observation**: Even though we requested 500Mi, we got the 1Gi PV because:
1. The storageClassName matched (`manual`)
2. The accessModes matched (`ReadWriteOnce`)
3. The capacity was sufficient (1Gi >= 500Mi)

### Step 3: Deploy a Pod Using the Storage

```bash
kubectl apply -f 02-fundamentals/03-pod-with-volume.yaml
```

Wait for the pod to be ready:

```bash
kubectl get pods -w
# Wait until STATUS shows "Running"
# Press Ctrl+C to exit
```

### Step 4: Test Data Persistence

This is the magic moment! Let's prove data survives pod deletion.

```bash
# Write data to the persistent volume
kubectl exec static-pod-demo -- sh -c "echo 'Hello from Kubernetes storage!' > /data/test.txt"

# Read it back
kubectl exec static-pod-demo -- cat /data/test.txt
# Output: Hello from Kubernetes storage!

# Now delete the pod
kubectl delete pod static-pod-demo

# Recreate the pod
kubectl apply -f 02-fundamentals/03-pod-with-volume.yaml

# Wait for it to start
kubectl wait --for=condition=ready pod/static-pod-demo --timeout=30s

# Check if data survived!
kubectl exec static-pod-demo -- cat /data/test.txt
# Output: Hello from Kubernetes storage!
```

🎉 **Success!** The data persisted even after the pod was deleted and recreated!

### Understanding What Happened

```
Timeline:
1. PV created (Available) → 2. PVC created → 3. Binding happens (Bound)
4. Pod created → 5. Volume mounted → 6. Data written
7. Pod deleted → 8. PV still bound → 9. Data preserved
10. New pod → 11. Same PVC → 12. Data still there!
```

---

## Lab 2: Dynamic Provisioning with StorageClasses

Static provisioning requires admins to pre-create PVs. **Dynamic provisioning** automatically creates PVs when PVCs are submitted. This is the modern approach.

### Step 1: Examine the Default StorageClass

```bash
kubectl get storageclass local-path -o yaml
```

Key fields:

```yaml
provisioner: rancher.io/local-path    # Who creates PVs
reclaimPolicy: Delete                  # What happens on PVC deletion
volumeBindingMode: WaitForFirstConsumer # When to create PV
```

### Step 2: Create a Dynamic PVC

```bash
cat 03-dynamic-provisioning/02-dynamic-pvc.yaml
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: dynamic-pvc-demo
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  # storageClassName omitted = use default StorageClass
```

Apply it:

```bash
kubectl apply -f 03-dynamic-provisioning/02-dynamic-pvc.yaml
```

Check the status:

```bash
kubectl get pvc dynamic-pvc-demo

# Output:
# NAME               STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
# dynamic-pvc-demo   Pending                                      local-path
```

🤔 **Why is it Pending?** Because of `WaitForFirstConsumer` mode! The PV won't be created until a pod uses this PVC.

### Step 3: Create a Pod to Trigger Provisioning

```bash
kubectl run dynamic-test --image=busybox:1.36 \
  --overrides='{"spec":{"containers":[{"name":"dynamic-test","image":"busybox:1.36","command":["sleep","infinity"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"dynamic-pvc-demo"}}]}}'
```

Now check:

```bash
kubectl get pvc,pv

# Output:
# NAME                                    STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
# persistentvolumeclaim/dynamic-pvc-demo  Bound    pvc-xxxxx                                  1Gi        RWO            local-path
```

The PVC is now Bound and a PV was automatically created!

### Step 4: Understand Reclaim Policies

Let's see what happens when we delete a PVC with `Delete` reclaim policy:

```bash
# First, create the custom StorageClasses (needed for the reclaim policy demo)
kubectl apply -f 03-dynamic-provisioning/01-storage-class.yaml

# Create the test resources (PVCs and pods with different reclaim policies)
kubectl apply -f 03-dynamic-provisioning/03-reclaim-policies.yaml

# Check what was created
kubectl get pvc delete-policy-pvc retain-policy-pvc
kubectl get pv

# Note the PV name for the delete-policy PVC
PV_NAME=$(kubectl get pvc delete-policy-pvc -o jsonpath='{.spec.volumeName}')
echo "PV Name: $PV_NAME"

# Delete the PVC
kubectl delete pvc delete-policy-pvc

# Check if PV still exists
kubectl get pv $PV_NAME
# Error: the PV was automatically deleted!

# Compare with retain-policy-pvc - delete it and check its PV
kubectl delete pvc retain-policy-pvc
kubectl get pv
# The PV remains with status 'Released'!
```

⚠️ **Warning**: In production, be very careful with `Delete` reclaim policy! Your data will be gone.

---

## Lab 3: StatefulSet Storage Patterns

StatefulSets are designed for stateful applications like databases. Each pod gets:
1. A stable hostname (pod-0, pod-1, pod-2)
2. Its own persistent storage that follows it

### Step 1: Create the Headless Service

StatefulSets require a headless service (ClusterIP: None):

```bash
kubectl apply -f 04-statefulsets/01-headless-service.yaml
```

### Step 2: Deploy the StatefulSet

```bash
cat 04-statefulsets/02-statefulset.yaml
```

Key section:

```yaml
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
        - ReadWriteOnce
      resources:
        requests:
          storage: 256Mi
```

This creates a PVC for each pod automatically!

Deploy it:

```bash
kubectl apply -f 04-statefulsets/02-statefulset.yaml
```

Watch pods come up **in order**:

```bash
kubectl get pods -l app=web -w
# web-0 → web-1 → web-2 (one after another)
```

### Step 3: Examine the Created PVCs

```bash
kubectl get pvc

# Output:
# NAME           STATUS   VOLUME                                     CAPACITY
# data-web-0     Bound    pvc-xxx                                    256Mi
# data-web-1     Bound    pvc-yyy                                    256Mi
# data-web-2     Bound    pvc-zzz                                    256Mi
```

Each pod has its own dedicated storage!

### Step 4: Test Per-Pod Persistence

```bash
# Write unique data to each pod
for i in 0 1 2; do
  kubectl exec web-$i -- sh -c "echo 'I am web-$i' > /usr/share/nginx/html/identity.txt"
done

# Verify each has different content
for i in 0 1 2; do
  echo "=== web-$i ==="
  kubectl exec web-$i -- cat /usr/share/nginx/html/identity.txt
done
```

Now test persistence:

```bash
# Delete pod web-1
kubectl delete pod web-1

# Wait for it to restart
kubectl wait --for=condition=ready pod/web-1 --timeout=60s

# Check if data survived!
kubectl exec web-1 -- cat /usr/share/nginx/html/identity.txt
# Output: I am web-1
```

🎉 **Amazing!** Each pod maintains its identity and data across restarts.

### Step 5: Scaling Behavior

```bash
# Scale up - new PVCs are created
kubectl scale statefulset web --replicas=5
kubectl get pvc

# Scale down - PVCs are RETAINED!
kubectl scale statefulset web --replicas=3
kubectl get pvc
# data-web-3 and data-web-4 still exist!

# Scale back up - pods reattach to existing PVCs!
kubectl scale statefulset web --replicas=5
```

This is crucial for databases — you never accidentally lose data when scaling.

---

## Lab 4: Access Modes Deep Dive

Understanding access modes is critical for multi-pod applications.

### ReadWriteOnce (RWO) — The Default

```bash
kubectl apply -f 05-access-modes/01-rwo-demo.yaml
```

RWO means only **one node** can mount the volume for read-write. Multiple pods on the **same node** can share it, but pods on different nodes cannot.

### The RWO Limitation Demo

```bash
kubectl apply -f 05-access-modes/03-multi-pod-conflict.yaml
```

Check pod status:

```bash
kubectl get pods -l demo=rwo-conflict

# Some pods may be stuck in Pending!
kubectl describe pod <pending-pod-name> | grep -A5 Events
```

You'll see an error like:
```
Warning  FailedScheduling  pod/rwo-test-2  volume node affinity conflict
```

### ReadWriteMany (RWX) — Shared Storage

RWX allows multiple nodes to mount the same volume read-write. This requires special storage backends:
- NFS
- CephFS
- Azure Files
- AWS EFS

```bash
kubectl apply -f 05-access-modes/02-rwx-demo.yaml
```

> ⚠️ **Note**: The `local-path` provisioner doesn't support RWX. For this demo to fully work, you'd need NFS or Rook-Ceph (covered in Lab 5).

### When to Use Each Mode

| Scenario | Access Mode |
|----------|-------------|
| Single database pod | RWO |
| Multiple pods reading config files | ROX |
| Multiple pods writing to shared storage | RWX |
| Strict single-writer requirement | RWOP |

---

## Lab 5: Production Storage with Rook-Ceph (Advanced)

For production workloads, you need distributed storage that can:
- Survive node failures
- Provide multiple access modes
- Offer different storage types (block, file, object)

**Rook-Ceph** is the answer. It deploys Ceph on Kubernetes.

### Quick Setup with k3d

```bash
cd 06-rook-ceph
./setup-k3d-rook.sh
```

This takes ~10 minutes and sets up:
- Rook Operator
- Ceph Cluster (using PVCs as backing storage for demo purposes)
- Block Storage (RBD)
- Shared Filesystem (CephFS)
- Object Storage (S3-compatible)

### What Rook-Ceph Provides

| Storage Type | Access Mode | Use Case |
|--------------|-------------|----------|
| **Block (RBD)** | RWO | Databases, single-pod workloads |
| **Filesystem (CephFS)** | RWX | Shared data, multi-pod apps |
| **Object (RGW)** | S3 API | Backups, media, large objects |

### Verify Ceph Health

```bash
kubectl -n rook-ceph get cephcluster
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```

For detailed Rook-Ceph instructions, see:
- `06-rook-ceph/README.md`
- `06-rook-ceph/k3d-guide.md`

---

## Troubleshooting Common Issues

### PVC Stuck in Pending

```bash
kubectl describe pvc <pvc-name>
```

**Common causes:**
1. ❌ No matching StorageClass
2. ❌ No available PV (static provisioning)
3. ❌ `WaitForFirstConsumer` waiting for pod
4. ❌ Insufficient cluster resources

**Solution checklist:**
```bash
# Check StorageClass exists
kubectl get storageclass

# Check for matching PVs (static provisioning)
kubectl get pv

# Check if provisioner pods are running
kubectl get pods -n kube-system | grep -i provision
```

### Pod Stuck in ContainerCreating

```bash
kubectl describe pod <pod-name>
```

Look for:
- "Unable to attach or mount volumes"
- "FailedMount"
- "volume node affinity conflict"

**Common fixes:**
```bash
# Check PVC is bound
kubectl get pvc

# Check node has the volume
kubectl get pv <pv-name> -o yaml | grep nodeAffinity

# Verify storage driver pods
kubectl get pods -n kube-system
```

### Data Corruption Debugging

For production debugging without affecting live pods:

```bash
# Create a debug pod with the same PVC
kubectl run debug-pod --image=busybox \
  --overrides='{"spec":{"containers":[{"name":"debug","image":"busybox","command":["sleep","infinity"],"volumeMounts":[{"name":"data","mountPath":"/data","readOnly":true}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"your-pvc","readOnly":true}}]}}'

# Inspect the data
kubectl exec debug-pod -- ls -la /data
kubectl exec debug-pod -- cat /data/some-file
```

---

## Key Takeaways & Next Steps

### What We Learned

1. **Storage Architecture**: PV → PVC → Pod binding flow
2. **Static vs Dynamic**: Manual PV creation vs StorageClass automation
3. **Access Modes**: RWO for single-node, RWX for shared access
4. **StatefulSets**: Per-pod storage with `volumeClaimTemplates`
5. **Reclaim Policies**: `Retain` for safety, `Delete` for cleanup
6. **Production Storage**: Rook-Ceph for distributed, resilient storage

### Best Practices

| Practice | Why |
|----------|-----|
| Always use `WaitForFirstConsumer` | Ensures topology-aware scheduling |
| Use `Retain` for production data | Prevents accidental data loss |
| Set resource requests/limits on PVCs | Prevents runaway storage usage |
| Monitor storage with Prometheus | Catch issues before they're critical |
| Regular backup with Velero | Disaster recovery |

### Next Steps

1. **Explore Rook-Ceph**: Set up block, filesystem, and object storage
2. **Add Velero**: Implement backup and disaster recovery
3. **Storage Metrics**: Set up Prometheus monitoring for PVCs
4. **GitOps Storage**: Manage StorageClasses with ArgoCD

---

## Cleanup

When you're done experimenting:

```bash
./08-cleanup.sh
```

This removes all resources and deletes the k3d cluster.

---

## Resources

📚 **Official Documentation:**
- [Kubernetes Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [StorageClasses](https://kubernetes.io/docs/concepts/storage/storage-classes/)
- [StatefulSets](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/)
- [Rook-Ceph](https://rook.io/docs/rook/latest-release/)

🔧 **Tools:**
- [k3d](https://k3d.io/) - Lightweight Kubernetes in Docker
- [Velero](https://velero.io/) - Backup and disaster recovery
- [CSI Spec](https://github.com/container-storage-interface/spec)

---

## Connect With Me

If you found this tutorial helpful:
- ⭐ Star the repository
- 🐦 Follow me on Twitter: [@your_handle]
- 💼 Connect on LinkedIn: [Your Profile]
- 📝 Subscribe to my newsletter for more Kubernetes content

**Happy Learning! 🚀**

---

*This article is part of my Kubernetes Deep Dive series. Check out the full course for more hands-on labs on networking, security, observability, and more.*
