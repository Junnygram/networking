# Shared Filesystem Storage (CephFS) with Rook-Ceph

## Overview

CephFS provides a POSIX-compliant shared filesystem that multiple pods can mount simultaneously (RWX - ReadWriteMany). This is ideal for:
- Shared application data
- Content management systems
- Machine learning datasets
- Log aggregation
- Any workload where multiple pods need shared read-write access

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                 CephFS Storage Flow                      │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   Pod A          Pod B          Pod C                   │
│   ┌────┐         ┌────┐         ┌────┐                 │
│   │/mnt│         │/mnt│         │/mnt│                 │
│   └──┬─┘         └──┬─┘         └──┬─┘                 │
│      │              │              │                    │
│      └──────────────┼──────────────┘                   │
│                     │                                   │
│                     ▼                                   │
│              ┌─────────────┐                           │
│              │     PVC     │                           │
│              │  RWX mode   │                           │
│              │ rook-cephfs │                           │
│              └─────────────┘                           │
│                     │                                   │
│                     ▼                                   │
│              ┌─────────────┐    ┌─────────────┐        │
│              │StorageClass │───►│CephFilesystem│       │
│              │ rook-cephfs │    │    myfs      │       │
│              └─────────────┘    └─────────────┘        │
│                                        │                │
│                     ┌──────────────────┼────────┐      │
│                     ▼                  ▼        ▼      │
│              ┌──────────┐      ┌──────────┐ ┌──────┐  │
│              │   MDS    │      │   MDS    │ │ OSD  │  │
│              │ (active) │      │(standby) │ │pools │  │
│              └──────────┘      └──────────┘ └──────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## Components

- **MDS (Metadata Server)**: Manages filesystem metadata (directories, file names, permissions)
- **Data Pool**: Stores actual file data (uses OSDs)
- **Metadata Pool**: Stores filesystem metadata

## Setup Steps

### Step 1: Create CephFilesystem

```bash
kubectl apply -f cephfilesystem.yaml
```

### Step 2: Verify MDS is Running

```bash
kubectl -n rook-ceph get pod -l app=rook-ceph-mds
```

### Step 3: Create StorageClass

```bash
kubectl apply -f storageclass.yaml
```

### Step 4: Test with Sample Application

```bash
kubectl apply -f test-app.yaml
```

## Verification

```bash
# Check filesystem status
kubectl -n rook-ceph get cephfilesystem

# Check MDS daemons
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph mds stat

# Verify filesystem health
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph fs status myfs
```

## Important Notes

- CephFS requires at least one MDS daemon
- MDS pods need significant memory (1-2GB recommended)
- Quota enforcement requires Linux kernel 4.17+
