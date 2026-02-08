# Block Storage (RBD) with Rook-Ceph

## Overview

Ceph Block Devices (RBD) provide high-performance block storage that can be mounted by a single pod (RWO). This is ideal for:
- Databases (PostgreSQL, MySQL, MongoDB)
- Message queues (RabbitMQ, Kafka)
- Any single-instance stateful application

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                  Block Storage Flow                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   Pod                                                    │
│   ┌──────────────┐                                      │
│   │  Container   │                                      │
│   │  /var/lib/db │ ◄── mounted via CSI                 │
│   └──────────────┘                                      │
│          │                                               │
│          ▼                                               │
│   ┌──────────────┐                                      │
│   │     PVC      │                                      │
│   │ rook-ceph-   │                                      │
│   │    block     │                                      │
│   └──────────────┘                                      │
│          │                                               │
│          ▼                                               │
│   ┌──────────────┐     ┌──────────────┐                │
│   │ StorageClass │────►│ CephBlockPool│                │
│   │ rook-ceph-   │     │  replicapool │                │
│   │    block     │     │  replicas: 3 │                │
│   └──────────────┘     └──────────────┘                │
│                               │                         │
│                               ▼                         │
│                     ┌─────────────────────┐            │
│                     │   Ceph Cluster      │            │
│                     │  OSD  OSD  OSD      │            │
│                     │  (data replicated)  │            │
│                     └─────────────────────┘            │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Setup Steps

### Step 1: Create CephBlockPool

```bash
kubectl apply -f cephblockpool.yaml
```

### Step 2: Create StorageClass

```bash
kubectl apply -f storageclass.yaml
```

### Step 3: Test with Sample Application

```bash
kubectl apply -f test-app.yaml
```

## Verification

```bash
# Check block pool status
kubectl -n rook-ceph get cephblockpool

# Check StorageClass
kubectl get storageclass rook-ceph-block

# Check PVC binding
kubectl get pvc

# Verify data replication in Ceph
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd pool ls detail
```
