# Changelog - k8s-storage Lab Updates

**Date:** 2026-02-06

This document tracks all changes made to ensure the tutorial files are consistent and work correctly with k3d clusters.

---

## Summary

The original files had inconsistencies between what the article/README documented and what the actual YAML files contained. Additionally, some files used KinD-specific configurations while the recommended setup uses k3d.

---

## Changes Made

### 6. `05-access-modes/02-rwx-demo.yaml`

**What changed:**
- Increased `nfs-server` container memory `limits` from `128Mi` to `256Mi`.

**Why:**
- The `nfs-server` pod was consistently getting `OOMKilled` (Out Of Memory) with the original `128Mi` memory limit, preventing the RWX demo from functioning. Increasing the limit provides more stability.

---

### 1. `03-dynamic-provisioning/02-dynamic-pvc.yaml`

**What changed:**
- Simplified from multiple PVCs to a single focused PVC
- Changed PVC name from `dynamic-default-pvc` → `dynamic-pvc-demo`
- Changed storage request from `256Mi` → `1Gi`
- Removed the pod definition from this file

**Why:**
- The article referenced `dynamic-pvc-demo` but the YAML had `dynamic-default-pvc` - caused "not found" errors when following along
- Removing the pod allows users to see the `WaitForFirstConsumer` behavior (PVC stays Pending until a pod uses it) - this is an important learning moment in the tutorial
- Simpler file makes it easier for beginners to understand the core concept

---

### 2. `ARTICLE.md` (Lab 2: Dynamic Provisioning section)

**What changed:**
- Updated PVC name references from `dynamic-default-pvc` → `dynamic-pvc-demo`
- Updated storage size from `256Mi` → `1Gi`
- Changed Step 3 from "Verify the Pod and Storage" → "Create a Pod to Trigger Provisioning"
- Restored the "Why is it Pending?" explanation
- Added step to create custom StorageClasses before reclaim policy demo

**Why:**
- Article now matches the actual YAML file - users can follow along without errors
- The tutorial flow now properly demonstrates `WaitForFirstConsumer` mode
- Added missing prerequisite (StorageClasses must exist before `03-reclaim-policies.yaml` works)

---

### 3. `README.md`

**What changed:**
- Line 238: `kubectl get storageclass standard` → `kubectl get storageclass local-path`
- Added step to create StorageClasses before reclaim policy demo
- Added `kubectl get pvc dynamic-pvc-demo` command
- Added `kubectl run dynamic-test...` command to trigger provisioning
- Updated cleanup description to mention k3d support

**Why:**
- `standard` is KinD's default StorageClass, but `local-path` is k3d's default - the recommended setup uses k3d
- StorageClasses in `01-storage-class.yaml` must be created before `03-reclaim-policies.yaml` can work
- Users need clear commands they can copy-paste that actually work

---

### 4. `08-cleanup.sh`

**What changed:**
- Added k3d cluster detection and cleanup support
- Now auto-detects whether k3d or KinD is being used
- Added cleanup of k3d storage directory (`~/k3d-storage/storage-lab`)
- Added `immediate-storage-class` to the list of StorageClasses to delete

**Why:**
- Original script only worked with KinD, but the tutorial recommends k3d
- k3d creates a host storage directory that should be cleaned up
- The `01-storage-class.yaml` file creates `immediate-storage-class` but it wasn't being cleaned up

---

### 5. `05-access-modes/03-multi-pod-conflict.yaml`

**What changed:**
- Line 40: `kubernetes.io/hostname: storage-lab-worker` → `kubernetes.io/hostname: k3d-storage-lab-agent-0`
- Line 68: `kubernetes.io/hostname: storage-lab-worker2` → `kubernetes.io/hostname: k3d-storage-lab-agent-1`

**Why:**
- The original node names were for KinD clusters (`storage-lab-worker`)
- k3d uses different node naming convention (`k3d-storage-lab-agent-X`)
- Without this fix, pods would be stuck in Pending state forever (no matching nodes)

---

## Testing the Changes

After these updates, run the full lab:

```bash
# Setup cluster
./01-setup-cluster-k3d.sh

# Lab 1: Static provisioning
kubectl apply -f 02-fundamentals/01-static-pv.yaml
kubectl apply -f 02-fundamentals/02-pvc-binding.yaml
kubectl apply -f 02-fundamentals/03-pod-with-volume.yaml

# Lab 2: Dynamic provisioning
kubectl apply -f 03-dynamic-provisioning/02-dynamic-pvc.yaml
kubectl get pvc dynamic-pvc-demo  # Should show Pending

# Create pod to trigger provisioning
kubectl run dynamic-test --image=busybox:1.36 \
  --overrides='{"spec":{"containers":[{"name":"dynamic-test","image":"busybox:1.36","command":["sleep","infinity"],"volumeMounts":[{"name":"data","mountPath":"/data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"dynamic-pvc-demo"}}]}}'

kubectl get pvc dynamic-pvc-demo  # Should now show Bound

# Lab 2 continued: Reclaim policies
kubectl apply -f 03-dynamic-provisioning/01-storage-class.yaml
kubectl apply -f 03-dynamic-provisioning/03-reclaim-policies.yaml

# Lab 3: StatefulSets
kubectl apply -f 04-statefulsets/01-headless-service.yaml
kubectl apply -f 04-statefulsets/02-statefulset.yaml

# Lab 4: Access modes
kubectl apply -f 05-access-modes/01-rwo-demo.yaml
kubectl apply -f 05-access-modes/03-multi-pod-conflict.yaml

# Cleanup
./08-cleanup.sh
```

---

## Files NOT Changed (Already Correct)

These files were already consistent and didn't need updates:

- `01-setup-cluster-k3d.sh` - Correct k3d setup
- `02-fundamentals/01-static-pv.yaml` - Uses `manual` StorageClass correctly
- `02-fundamentals/02-pvc-binding.yaml` - Matches article
- `02-fundamentals/03-pod-with-volume.yaml` - Matches article
- `03-dynamic-provisioning/01-storage-class.yaml` - Custom StorageClasses
- `03-dynamic-provisioning/03-reclaim-policies.yaml` - Uses custom StorageClasses
- `04-statefulsets/` - All files consistent
- `05-access-modes/01-rwo-demo.yaml` - Uses pod affinity (works on any cluster)
- `05-access-modes/02-rwx-demo.yaml` - NFS example
