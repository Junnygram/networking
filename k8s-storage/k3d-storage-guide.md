# Kubernetes Storage with k3d

## Overview

k3d runs k3s (lightweight Kubernetes) inside Docker containers. It comes with several advantages for storage labs:

- **Built-in local-path-provisioner**: Dynamic provisioning works out of the box
- **Simpler setup**: No need to install additional CSI drivers
- **Faster startup**: k3s is lightweight and boots quickly

---

## Quick Start

### 1. Create Cluster

```bash
./01-setup-cluster-k3d.sh
```

Or manually:

```bash
# Create storage directory
mkdir -p ~/k3d-storage/storage-lab

# Create cluster with storage volume
k3d cluster create storage-lab \
    --servers 1 \
    --agents 3 \
    --volume ~/k3d-storage/storage-lab:/var/lib/rancher/k3s/storage@all \
    --port "30000-30100:30000-30100@server:0"
```

### 2. Verify Storage Class

```bash
kubectl get storageclass
```

Expected output:
```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false
```

---

## Understanding k3s Storage

### Local Path Provisioner

k3s includes [Rancher's Local Path Provisioner](https://github.com/rancher/local-path-provisioner) which:

1. Watches for PVCs requesting the `local-path` StorageClass
2. Creates directories on the node where the pod is scheduled
3. Creates a PV bound to that directory
4. Mounts the directory into the pod

**Default storage path:** `/var/lib/rancher/k3s/storage`

### Volume Mapping in k3d

Since k3d runs k3s inside Docker containers, the storage path is inside the container. To persist data and access it from your host:

```bash
k3d cluster create my-cluster \
    --volume /path/on/host:/var/lib/rancher/k3s/storage@all
```

The `@all` suffix means mount on all nodes.

---

## Storage Exercises with k3d

### Exercise 1: Dynamic Provisioning

```bash
# Create a PVC - PV will be created automatically
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: k3d-test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
  storageClassName: local-path
EOF

# Create a pod using the PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: k3d-test-pod
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo 'Hello from k3d!' > /data/test.txt && sleep infinity"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: k3d-test-pvc
EOF

# Wait and verify
kubectl wait --for=condition=ready pod k3d-test-pod --timeout=60s
kubectl exec k3d-test-pod -- cat /data/test.txt

# Check PVC and PV
kubectl get pvc,pv
```

### Exercise 2: Verify Data Persistence

```bash
# Note where the data is stored on host
ls -la ~/k3d-storage/storage-lab/

# Delete the pod (not the PVC)
kubectl delete pod k3d-test-pod

# Recreate the pod
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: k3d-test-pod
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "infinity"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: k3d-test-pvc
EOF

# Verify data persisted
kubectl wait --for=condition=ready pod k3d-test-pod --timeout=60s
kubectl exec k3d-test-pod -- cat /data/test.txt
```

### Exercise 3: StatefulSet with k3d

```bash
# Apply from the lab files
kubectl apply -f 04-statefulsets/01-headless-service.yaml
kubectl apply -f 04-statefulsets/02-statefulset.yaml

# Watch pods come up
kubectl get pods -w -l app=web

# Each pod gets its own PVC
kubectl get pvc

# Test persistence
./04-statefulsets/03-test-persistence.sh
```

---

## Custom StorageClass for k3d

Create a StorageClass with different settings:

```yaml
# k3d-retain-storage-class.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path-retain
provisioner: rancher.io/local-path
reclaimPolicy: Retain  # Keep data after PVC deletion
volumeBindingMode: WaitForFirstConsumer
```

```bash
kubectl apply -f k3d-retain-storage-class.yaml
```

---

## Limitations of k3d Storage

| Feature | Support | Notes |
|---------|---------|-------|
| Dynamic Provisioning | ✅ | Works out of the box |
| ReadWriteOnce (RWO) | ✅ | Default access mode |
| ReadWriteMany (RWX) | ❌ | local-path doesn't support RWX |
| Volume Expansion | ❌ | Not supported by local-path |
| Snapshots | ❌ | Not supported |
| Block Mode | ❌ | Only filesystem mode |

**For RWX support**, you need additional storage backends like:
- NFS server in cluster (see `05-access-modes/02-rwx-demo.yaml`)
- Rook-Ceph CephFS (requires proper environment)
- Longhorn

---

## Accessing Data on Host

When you mount storage with `--volume`, you can access PV data directly:

```bash
# List all PV directories
ls -la ~/k3d-storage/storage-lab/

# Each PVC gets a directory named: pvc-<uuid>_<namespace>_<pvc-name>
# Example: pvc-abc123_default_k3d-test-pvc
```

This is useful for:
- Debugging storage issues
- Backing up data
- Pre-populating volumes

---

## Troubleshooting k3d Storage

### PVC Stuck in Pending

```bash
kubectl describe pvc <pvc-name>
```

Common causes:
- **WaitForFirstConsumer**: Create a pod using the PVC
- **StorageClass not found**: Verify with `kubectl get sc`

### Pod Can't Mount Volume

```bash
kubectl describe pod <pod-name>
```

Check:
- Volume mount permissions
- PVC is bound
- Node has storage available

### Data Not Persisting After Cluster Recreation

Ensure you used `--volume` when creating the cluster:
```bash
k3d cluster create --volume ~/k3d-storage:/var/lib/rancher/k3s/storage@all
```

### Check Provisioner Logs

```bash
kubectl logs -n kube-system -l app=local-path-provisioner
```

---

## Cleanup

```bash
# Delete test resources
kubectl delete pod k3d-test-pod
kubectl delete pvc k3d-test-pvc

# Delete cluster
k3d cluster delete storage-lab

# Optionally remove storage directory
rm -rf ~/k3d-storage/storage-lab
```

---

## Next Steps

- Complete the exercises in `02-fundamentals/` through `05-access-modes/`
- For production-grade storage, see `06-rook-ceph/k3d-guide.md`
- For troubleshooting, see `07-troubleshooting/README.md`

---

## References

- [k3s Storage Documentation](https://docs.k3s.io/storage)
- [k3d Volume Documentation](https://k3d.io/v5.6.0/usage/k3s/#primitives)
- [Local Path Provisioner GitHub](https://github.com/rancher/local-path-provisioner)
- [How Local Path Provisioner Works](https://www.fadhil-blog.dev/blog/rancher-local-path-provisioner/)
