# Rook-Ceph: Production-Grade Distributed Storage

## Overview

Rook is a storage orchestrator that turns distributed storage systems into self-managing, self-scaling, self-healing storage services. Ceph is a highly scalable distributed storage solution providing object, block, and file storage.

Together, Rook-Ceph provides:
- **Block Storage (RBD)**: High-performance storage for databases and single-pod workloads
- **Shared Filesystem (CephFS)**: Multi-pod read-write access for shared data
- **Object Storage (RGW)**: S3-compatible API for application data

**Why Rook-Ceph?**
- Self-healing: Automatic recovery from node failures
- Scalable: Add capacity by adding nodes
- No vendor lock-in: Run anywhere with raw disks
- Kubernetes-native: Managed via CRDs

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Rook-Ceph Architecture                       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│   ┌─────────────┐     ┌─────────────┐     ┌─────────────┐          │
│   │   Node 1    │     │   Node 2    │     │   Node 3    │          │
│   │             │     │             │     │             │          │
│   │  ┌───────┐  │     │  ┌───────┐  │     │  ┌───────┐  │          │
│   │  │  OSD  │  │     │  │  OSD  │  │     │  │  OSD  │  │          │
│   │  │ (disk)│  │     │  │ (disk)│  │     │  │ (disk)│  │          │
│   │  └───────┘  │     │  └───────┘  │     │  └───────┘  │          │
│   │             │     │             │     │             │          │
│   │  ┌───────┐  │     │  ┌───────┐  │     │  ┌───────┐  │          │
│   │  │  MON  │  │     │  │  MON  │  │     │  │  MON  │  │          │
│   │  └───────┘  │     │  └───────┘  │     │  └───────┘  │          │
│   └─────────────┘     └─────────────┘     └─────────────┘          │
│                                                                      │
│   Components:                                                        │
│   - MON: Monitors - maintain cluster state (need 3 for quorum)      │
│   - OSD: Object Storage Daemons - one per disk, store actual data   │
│   - MGR: Managers - monitoring, metrics, dashboard                  │
│   - MDS: Metadata Servers - required for CephFS only                │
│   - RGW: RADOS Gateway - S3/Swift API for object storage            │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Prerequisites

### Hardware Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Nodes | 3 | 3+ |
| vCPU per node | 2 | 4+ |
| RAM per node | 4GB | 8GB+ |
| Raw disk per node | 10GB | 100GB+ |

### Storage Requirements

Ceph requires **raw, unformatted storage**. This can be:
- Raw block devices (`/dev/sdb`, `/dev/nvme0n1`)
- Raw partitions (unformatted)
- LVM logical volumes (unformatted)
- PVs in block mode (cloud environments)

**NOT supported:**
- Loop devices (KinD limitation)
- Already-formatted filesystems
- Root disk partitions

### Verify Raw Devices

```bash
# SSH to each node and check for raw devices
lsblk -f

# Look for devices with no FSTYPE (unformatted)
# Example output:
# NAME   FSTYPE  MOUNTPOINT
# sda
# └─sda1 ext4    /
# sdb             <- This is a raw device, good for Ceph!
# sdc             <- Another raw device
```

---

## Important: KinD Limitations

**Rook-Ceph does NOT work well with KinD** because:
1. KinD nodes are Docker containers, not real machines
2. No real block devices available
3. Loopback devices are not supported by Rook

**For learning Rook-Ceph, use one of these instead:**
- **VMs with attached disks** (Vagrant, VirtualBox, VMware)
- **Cloud instances** (AWS EC2 with EBS, GCP with persistent disks)
- **Bare metal** servers with spare disks
- **Minikube** with `--disk-size` and proper setup

The examples in this directory are designed for environments with real storage.

---

## Quick Start (Production Environment)

### Step 1: Clone Rook Repository

```bash
git clone --single-branch --branch v1.14.0 https://github.com/rook/rook.git
cd rook/deploy/examples
```

### Step 2: Deploy Rook Operator

```bash
# Create CRDs and common resources
kubectl create -f crds.yaml -f common.yaml

# Deploy the operator
kubectl create -f operator.yaml

# Wait for operator to be ready
kubectl -n rook-ceph get pod -l app=rook-ceph-operator -w
```

### Step 3: Create Ceph Cluster

```bash
# For production (3+ nodes with raw devices):
kubectl create -f cluster.yaml

# For testing (single node, less redundancy):
kubectl create -f cluster-test.yaml

# Monitor cluster creation (takes several minutes)
kubectl -n rook-ceph get pod -w
```

### Step 4: Verify Cluster Health

```bash
# Deploy the toolbox for cluster management
kubectl create -f toolbox.yaml

# Wait for toolbox
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-tools --timeout=60s

# Check cluster status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
```

Expected healthy output:
```
cluster:
  id:     xxxxx
  health: HEALTH_OK

services:
  mon: 3 daemons, quorum a,b,c
  mgr: a(active)
  osd: 3 osds: 3 up, 3 in
```

---

## Storage Types

### 1. Block Storage (RBD)

Best for: Databases, single-pod workloads needing high performance

See: `04-block-storage/`

### 2. Shared Filesystem (CephFS)

Best for: Multiple pods sharing data, content management, shared configs

See: `05-filesystem-storage/`

### 3. Object Storage (RGW)

Best for: S3-compatible API access, backups, media storage

See: `06-object-storage/`

---

## Troubleshooting

### Check OSD Status

```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd status
```

### View Cluster Logs

```bash
kubectl -n rook-ceph logs -l app=rook-ceph-operator --tail=100
```

### Common Issues

| Issue | Solution |
|-------|----------|
| No OSDs created | Verify raw devices exist with `lsblk -f` |
| MONs not reaching quorum | Check node connectivity and resource limits |
| PVC stuck pending | Verify StorageClass and CephBlockPool exist |
| Cluster health WARN | Run `ceph health detail` in toolbox |

---

## Cleanup

```bash
# Delete storage resources first
kubectl delete -n rook-ceph cephblockpool replicapool
kubectl delete storageclass rook-ceph-block

# Delete cluster
kubectl -n rook-ceph delete cephcluster rook-ceph

# Delete operator and CRDs
kubectl delete -f operator.yaml
kubectl delete -f common.yaml
kubectl delete -f crds.yaml

# Clean up data on nodes (SSH to each node)
rm -rf /var/lib/rook
```

---

## References

- [Rook Documentation](https://rook.io/docs/rook/latest-release/)
- [Ceph Documentation](https://docs.ceph.com/)
- [Rook GitHub Examples](https://github.com/rook/rook/tree/release-1.14/deploy/examples)
- [CloudOps Rook-Ceph Survival Guide](https://www.cloudops.com/blog/the-ultimate-rook-and-ceph-survival-guide/)
