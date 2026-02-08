# Rook-Ceph with k3d

## Overview

Rook-Ceph **can** run on k3s (which k3d uses), but there are important considerations because k3d runs Kubernetes inside Docker containers.

### The Challenge

Rook-Ceph needs **raw block devices** (unformatted disks) for its OSDs. In k3d:
- Nodes are Docker containers, not VMs
- No real block devices are available
- Loop devices have limited support

### Solutions

| Approach | Difficulty | Best For |
|----------|------------|----------|
| **Loop devices** | Medium | Testing/Learning |
| **PVC-backed OSDs** | Medium | Cloud-like environments |
| **k3s on VMs** | Higher | Production-like testing |

---

## Option 1: Loop Devices (Testing Only)

Create loop devices inside k3d containers to simulate block storage.

### Step 1: Create k3d Cluster

```bash
k3d cluster create rook-lab \
    --servers 1 \
    --agents 3 \
    --volume /tmp/k3d-rook:/var/lib/rook@all
```

### Step 2: Create Loop Devices on Each Agent

```bash
#!/bin/bash
# Run this for each agent node

for node in k3d-rook-lab-agent-0 k3d-rook-lab-agent-1 k3d-rook-lab-agent-2; do
    echo "Setting up loop device on ${node}..."

    # Create a 10GB file for the loop device
    docker exec ${node} sh -c '
        mkdir -p /var/lib/rook
        dd if=/dev/zero of=/var/lib/rook/ceph-disk.img bs=1M count=10240
        losetup -fP /var/lib/rook/ceph-disk.img
        losetup -a
    '
done
```

### Step 3: Deploy Rook Operator

```bash
git clone --single-branch --branch v1.14.0 https://github.com/rook/rook.git /tmp/rook
cd /tmp/rook/deploy/examples

kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-operator --timeout=300s
```

### Step 4: Create Cluster with Loop Device Config

```yaml
# cluster-k3d-loop.yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.2
  dataDirHostPath: /var/lib/rook
  mon:
    count: 1
    allowMultiplePerNode: true
  mgr:
    count: 1
    allowMultiplePerNode: true
  dashboard:
    enabled: true
  storage:
    useAllNodes: true
    useAllDevices: false
    # Specify the loop device
    devices:
      - name: "loop0"
    config:
      osdsPerDevice: "1"
```

```bash
kubectl apply -f cluster-k3d-loop.yaml
```

**⚠️ Warning:** Loop devices are unreliable for Ceph. This is for learning only!

---

## Option 2: PVC-Backed OSDs (Recommended for k3d)

Use existing storage (local-path) to back Ceph OSDs. This creates a "storage on storage" setup but works reliably in k3d.

### Step 1: Create k3d Cluster with Storage

```bash
mkdir -p ~/k3d-rook-storage

k3d cluster create rook-lab \
    --servers 1 \
    --agents 3 \
    --volume ~/k3d-rook-storage:/var/lib/rancher/k3s/storage@all \
    --volume ~/k3d-rook-storage/rook:/var/lib/rook@all
```

### Step 2: Deploy Rook Operator

```bash
git clone --single-branch --branch v1.14.0 https://github.com/rook/rook.git /tmp/rook
cd /tmp/rook/deploy/examples

kubectl create -f crds.yaml -f common.yaml -f operator.yaml
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-operator --timeout=300s
```

### Step 3: Create Cluster with PVC-backed OSDs

```yaml
# cluster-k3d-pvc.yaml
apiVersion: ceph.rook.io/v1
kind: CephCluster
metadata:
  name: rook-ceph
  namespace: rook-ceph
spec:
  cephVersion:
    image: quay.io/ceph/ceph:v18.2.2
    allowUnsupported: true
  dataDirHostPath: /var/lib/rook

  mon:
    count: 1
    allowMultiplePerNode: true
    volumeClaimTemplate:
      spec:
        storageClassName: local-path
        resources:
          requests:
            storage: 2Gi

  mgr:
    count: 1
    allowMultiplePerNode: true

  dashboard:
    enabled: true
    ssl: false

  network:
    connections:
      encryption:
        enabled: false
      compression:
        enabled: false

  # PVC-backed storage
  storage:
    storageClassDeviceSets:
      - name: set1
        count: 3
        portable: false
        tuneDeviceClass: true
        tuneFastDeviceClass: false
        encrypted: false
        placement:
          topologySpreadConstraints:
            - maxSkew: 1
              topologyKey: kubernetes.io/hostname
              whenUnsatisfiable: ScheduleAnyway
              labelSelector:
                matchLabels:
                  app: rook-ceph-osd
        volumeClaimTemplates:
          - metadata:
              name: data
            spec:
              resources:
                requests:
                  storage: 5Gi
              storageClassName: local-path
              volumeMode: Block
              accessModes:
                - ReadWriteOnce

  resources:
    mgr:
      limits:
        memory: "512Mi"
      requests:
        cpu: "100m"
        memory: "256Mi"
    mon:
      limits:
        memory: "512Mi"
      requests:
        cpu: "100m"
        memory: "256Mi"
    osd:
      limits:
        memory: "1Gi"
      requests:
        cpu: "100m"
        memory: "512Mi"
```

```bash
kubectl apply -f cluster-k3d-pvc.yaml
```

### Step 4: Wait for Cluster to Be Ready

```bash
# Watch pods come up (takes several minutes)
kubectl -n rook-ceph get pods -w

# Once OSD pods are running, check cluster health
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```

---

## Option 3: k3s on VMs (Most Realistic)

For the most realistic Rook-Ceph experience, run k3s on actual VMs with attached disks.

### Using Multipass (Quick VM Setup)

```bash
#!/bin/bash
# Create 3 VMs with extra disk

for i in 1 2 3; do
    multipass launch --name k3s-node-$i \
        --cpus 2 \
        --memory 4G \
        --disk 20G

    # Add extra disk for Ceph
    # Note: Multipass doesn't support multiple disks directly
    # You'd need to use VirtualBox/Vagrant for true multi-disk VMs
done

# Install k3s on first node (server)
multipass exec k3s-node-1 -- bash -c '
    curl -sfL https://get.k3s.io | sh -s - server --cluster-init
'

# Get token
TOKEN=$(multipass exec k3s-node-1 -- sudo cat /var/lib/rancher/k3s/server/node-token)
SERVER_IP=$(multipass info k3s-node-1 | grep IPv4 | awk "{print \$2}")

# Join other nodes
for i in 2 3; do
    multipass exec k3s-node-$i -- bash -c "
        curl -sfL https://get.k3s.io | K3S_URL=https://${SERVER_IP}:6443 K3S_TOKEN=${TOKEN} sh -
    "
done
```

### Using Vagrant (Recommended)

See `01-prerequisites.md` for a complete Vagrant setup with attached disks.

---

## Verifying Rook-Ceph Installation

### Deploy Toolbox

```bash
kubectl apply -f /tmp/rook/deploy/examples/toolbox.yaml
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-tools --timeout=120s
```

### Check Cluster Status

```bash
# Cluster health
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status

# OSD status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd status

# Storage capacity
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph df
```

### Create Block Storage

```bash
# Apply block pool and storage class
kubectl apply -f 04-block-storage/cephblockpool.yaml
kubectl apply -f 04-block-storage/storageclass.yaml

# Test with MySQL
kubectl apply -f 04-block-storage/test-app.yaml
```

### Create Shared Filesystem

```bash
# Apply CephFS configuration
kubectl apply -f 05-filesystem-storage/cephfilesystem.yaml
kubectl apply -f 05-filesystem-storage/storageclass.yaml

# Wait for MDS
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-mds --timeout=300s

# Test shared storage
kubectl apply -f 05-filesystem-storage/test-app.yaml
```

---

## Troubleshooting k3d + Rook

### OSDs Not Starting

```bash
# Check OSD prepare job logs
kubectl -n rook-ceph logs -l app=rook-ceph-osd-prepare

# Check if PVCs are bound (for PVC-backed OSDs)
kubectl -n rook-ceph get pvc
```

### Monitor Not Starting

```bash
# Check mon pod logs
kubectl -n rook-ceph logs -l app=rook-ceph-mon

# Verify mon PVC is bound
kubectl -n rook-ceph get pvc -l app=rook-ceph-mon
```

### Cluster Health Warnings

```bash
# Get detailed health info
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph health detail

# Check for slow operations
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph daemon mon.a perf dump
```

### Resource Issues

k3d containers have limited resources. If pods are getting OOMKilled:

```bash
# Check resource usage
kubectl top pods -n rook-ceph

# Reduce resource requests in cluster.yaml
```

---

## Performance Considerations

Running Rook-Ceph on k3d has significant performance overhead:

| Layer | Overhead |
|-------|----------|
| k3d (Docker) | Container overhead |
| local-path | Filesystem on container |
| Ceph OSD on PVC | Another filesystem layer |
| Ceph RBD/CephFS | Ceph protocols |

**This is fine for learning but NOT for performance testing!**

For realistic performance:
- Use VMs with dedicated disks
- Use bare metal
- Use cloud instances with direct-attached storage

---

## Cleanup

```bash
# Delete Ceph cluster (wait for cleanup)
kubectl -n rook-ceph delete cephcluster rook-ceph
sleep 60

# Delete operator
kubectl delete -f /tmp/rook/deploy/examples/operator.yaml
kubectl delete -f /tmp/rook/deploy/examples/common.yaml
kubectl delete -f /tmp/rook/deploy/examples/crds.yaml

# Delete k3d cluster
k3d cluster delete rook-lab

# Clean up storage
rm -rf ~/k3d-rook-storage
```

---

## Summary

| Approach | Works in k3d? | Production Ready? | Best For |
|----------|---------------|-------------------|----------|
| Loop devices | Partially | No | Quick testing |
| PVC-backed OSDs | Yes | No | Learning/demos |
| k3s on VMs | Yes | Yes (with proper HW) | Realistic testing |

For comprehensive Rook-Ceph learning, we recommend:
1. Start with PVC-backed OSDs in k3d to understand concepts
2. Move to VMs with real disks for realistic testing
3. Use bare metal or cloud for production

---

## References

- [Rook on k3s (Medium)](https://itnext.io/using-rook-on-a-k3s-cluster-8a97a75ba25e)
- [k3s-rook GitHub Project](https://github.com/stblassitude/k3s-rook)
- [Rook PVC-backed Clusters](https://rook.io/docs/rook/latest-release/CRDs/Cluster/pvc-cluster/)
- [Tech by K: Rook on k3s](https://techbyk.com/?p=608)
