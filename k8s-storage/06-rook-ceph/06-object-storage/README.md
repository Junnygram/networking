# Object Storage (RGW) with Rook-Ceph

## Overview

Ceph Object Gateway (RGW) provides an S3-compatible API for object storage. This is ideal for:
- Application data storage (images, documents, media)
- Backup storage
- Data lakes
- Static website hosting
- Any application designed for S3-compatible storage

## How It Works

```
┌─────────────────────────────────────────────────────────┐
│                  Object Storage Flow                     │
├─────────────────────────────────────────────────────────┤
│                                                          │
│   Application                                            │
│   ┌─────────────────┐                                   │
│   │  S3 SDK/CLI     │                                   │
│   │  aws s3 cp ...  │                                   │
│   └────────┬────────┘                                   │
│            │ HTTPS                                       │
│            ▼                                             │
│   ┌─────────────────┐                                   │
│   │   Kubernetes    │                                   │
│   │    Service      │                                   │
│   └────────┬────────┘                                   │
│            │                                             │
│            ▼                                             │
│   ┌─────────────────┐    ┌─────────────────┐           │
│   │      RGW        │───►│ CephObjectStore │           │
│   │   (Gateway)     │    │   my-store      │           │
│   └─────────────────┘    └─────────────────┘           │
│            │                                             │
│            ▼                                             │
│   ┌─────────────────────────────────────────┐          │
│   │           Ceph Cluster                   │          │
│   │   ┌─────┐  ┌─────┐  ┌─────┐            │          │
│   │   │ OSD │  │ OSD │  │ OSD │            │          │
│   │   └─────┘  └─────┘  └─────┘            │          │
│   └─────────────────────────────────────────┘          │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Components

- **RGW (RADOS Gateway)**: HTTP/HTTPS frontend providing S3/Swift API
- **CephObjectStore**: Custom resource defining the object storage configuration
- **CephObjectStoreUser**: Credentials for accessing the object store
- **ObjectBucketClaim**: Dynamic bucket provisioning (like PVC for buckets)

## Setup Steps

### Step 1: Create Object Store

```bash
kubectl apply -f cephobjectstore.yaml
```

### Step 2: Verify RGW is Running

```bash
kubectl -n rook-ceph get pod -l app=rook-ceph-rgw
```

### Step 3: Create User for Access

```bash
kubectl apply -f object-user.yaml
```

### Step 4: Get Access Keys

```bash
kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o jsonpath='{.data.AccessKey}' | base64 -d
kubectl -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o jsonpath='{.data.SecretKey}' | base64 -d
```

### Step 5: Test Access

```bash
kubectl apply -f test-app.yaml
```

## Verification

```bash
# Check object store status
kubectl -n rook-ceph get cephobjectstore

# Check RGW endpoint
kubectl -n rook-ceph get svc rook-ceph-rgw-my-store

# List buckets via toolbox
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- radosgw-admin bucket list
```

## S3 API Usage

```bash
# Configure AWS CLI
export AWS_ACCESS_KEY_ID=<from secret>
export AWS_SECRET_ACCESS_KEY=<from secret>
export AWS_ENDPOINT_URL=http://<rgw-service>:80

# Create bucket
aws --endpoint-url=$AWS_ENDPOINT_URL s3 mb s3://my-bucket

# Upload file
aws --endpoint-url=$AWS_ENDPOINT_URL s3 cp myfile.txt s3://my-bucket/

# List objects
aws --endpoint-url=$AWS_ENDPOINT_URL s3 ls s3://my-bucket/
```
