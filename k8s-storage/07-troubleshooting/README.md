# Storage Troubleshooting Guide

## Common Issues and Solutions

This guide covers the most common storage problems you'll encounter in Kubernetes.

---

## PVC Issues

### PVC Stuck in Pending

**Symptoms:**
```bash
$ kubectl get pvc
NAME      STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS
my-pvc    Pending                                       standard
```

**Diagnosis:**
```bash
kubectl describe pvc my-pvc
```

**Common Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| No matching PV (static provisioning) | Create a PV with matching capacity, access modes, and storageClassName |
| StorageClass doesn't exist | Create the StorageClass or use an existing one |
| Provisioner not running | Check CSI driver pods: `kubectl get pods -n kube-system -l app=csi` |
| WaitForFirstConsumer mode | Create a pod that uses the PVC - it will bind when scheduled |
| Insufficient storage | Check available capacity with your storage backend |

**Quick Fix:**
```bash
# Check if StorageClass exists
kubectl get storageclass

# Check provisioner pods
kubectl get pods -A | grep -i csi

# Check events
kubectl get events --field-selector involvedObject.name=my-pvc
```

---

### PVC Bound but Pod Can't Use It

**Symptoms:**
- Pod stuck in `ContainerCreating`
- Pod events show volume mount errors

**Diagnosis:**
```bash
kubectl describe pod my-pod
kubectl get events --field-selector involvedObject.name=my-pod
```

**Common Causes:**

1. **Multi-Attach Error (RWO volume on different node)**
   ```
   Warning  FailedAttachVolume  Multi-Attach error for volume "pvc-xxx"
   ```
   **Solution:** Ensure pod is scheduled on the same node as the original pod, or use RWX storage.

2. **Node doesn't have CSI driver**
   ```
   Warning  FailedMount  Unable to attach or mount volumes
   ```
   **Solution:** Verify CSI driver DaemonSet is running on all nodes.

3. **Volume already attached to terminated pod**
   **Solution:** Force delete the stuck pod:
   ```bash
   kubectl delete pod stuck-pod --grace-period=0 --force
   ```

---

## StatefulSet Storage Issues

### PVCs Not Being Created

**Diagnosis:**
```bash
kubectl get pvc -l app=my-statefulset
kubectl describe statefulset my-statefulset
```

**Common Causes:**

1. **volumeClaimTemplates syntax error**
   - Verify YAML indentation
   - Check that `accessModes` and `resources` are correct

2. **StorageClass not found**
   - Verify the storageClassName exists
   - If omitted, ensure a default StorageClass is set

### Pods Stuck After Scaling Down Then Up

**Issue:** PVCs exist but pods can't bind to them.

**Solution:**
```bash
# Delete the problematic PVC and let StatefulSet recreate
kubectl delete pvc data-web-2
# Then scale back up
kubectl scale statefulset web --replicas=3
```

---

## Node Storage Issues

### Node Out of Disk Space

**Symptoms:**
- Pods evicted with `DiskPressure`
- New pods can't be scheduled

**Diagnosis:**
```bash
kubectl describe node <node-name> | grep -A5 Conditions
```

**Solutions:**

1. **Clean up unused images:**
   ```bash
   docker system prune -a
   # or for containerd
   crictl rmi --prune
   ```

2. **Clean up old PVs:**
   ```bash
   kubectl get pv | grep Released
   kubectl delete pv <released-pv-name>
   ```

3. **Expand node disk** (cloud provider specific)

---

## Rook-Ceph Specific Issues

### OSD Not Starting

**Diagnosis:**
```bash
kubectl -n rook-ceph get pods -l app=rook-ceph-osd
kubectl -n rook-ceph logs <osd-pod-name>
```

**Common Causes:**

1. **No raw devices found**
   ```bash
   # Check for raw devices on nodes
   lsblk -f
   # Devices must have NO filesystem
   ```

2. **Device already used by another OSD**
   ```bash
   # Clean the device
   sgdisk --zap-all /dev/sdX
   dd if=/dev/zero of=/dev/sdX bs=1M count=100
   ```

3. **LVM volumes on device**
   ```bash
   # Remove LVM metadata
   pvremove /dev/sdX
   vgremove <vg-name>
   ```

### Cluster Health Warning

**Diagnosis:**
```bash
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph health detail
```

**Common Warnings:**

1. **HEALTH_WARN: clock skew detected**
   - Synchronize time on all nodes: `sudo systemctl restart chronyd`

2. **HEALTH_WARN: X pools have too few placement groups**
   - Auto-scaler will fix this, or manually:
   ```bash
   ceph osd pool set <pool> pg_num <new-value>
   ```

3. **HEALTH_WARN: X osds down**
   - Check OSD pod status and logs
   - Verify node connectivity

### CephFS MDS Not Starting

**Diagnosis:**
```bash
kubectl -n rook-ceph get pods -l app=rook-ceph-mds
kubectl -n rook-ceph logs <mds-pod-name>
```

**Solution:** Usually resource-related. Increase MDS memory limits.

---

## Volume Expansion Issues

### Expansion Not Working

**Requirements:**
1. StorageClass must have `allowVolumeExpansion: true`
2. CSI driver must support expansion
3. Filesystem must support online resize (ext4, xfs do; some don't)

**Process:**
```bash
# Edit PVC to increase size
kubectl patch pvc my-pvc -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'

# Check expansion status
kubectl get pvc my-pvc -o yaml | grep -A5 status
```

**If stuck:**
```bash
# Check events
kubectl describe pvc my-pvc

# May need to restart pod for filesystem resize
kubectl delete pod <pod-using-pvc>
```

---

## Data Recovery

### Accidental PVC Deletion

**If reclaimPolicy was Retain:**
```bash
# Find the retained PV
kubectl get pv | grep Released

# Remove claimRef to make it Available
kubectl patch pv <pv-name> -p '{"spec":{"claimRef":null}}'

# Create new PVC with same specs
kubectl apply -f recovered-pvc.yaml
```

**If reclaimPolicy was Delete:**
- Data is gone. Restore from backup.
- Always use Retain for important data!

### Recover Data from Released PV

```bash
# Create a temporary PVC that binds to the released PV
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: recovery-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: <same-as-pv>
  storageClassName: ""  # Important: empty string
  volumeName: <pv-name>  # Bind to specific PV
```

---

## Debugging Commands Cheat Sheet

```bash
# General
kubectl get pv,pvc -A
kubectl describe pvc <name>
kubectl get events --sort-by='.lastTimestamp'

# CSI driver
kubectl get csidrivers
kubectl get pods -n kube-system -l app=csi

# Storage classes
kubectl get storageclass
kubectl describe storageclass <name>

# Node storage
kubectl describe node <name> | grep -A10 "Allocated resources"

# Rook-Ceph
kubectl -n rook-ceph get pods
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph df

# Volume info for a pod
kubectl get pod <name> -o jsonpath='{.spec.volumes[*].persistentVolumeClaim.claimName}'
```

---

## Prevention Best Practices

1. **Always use StorageClass with appropriate reclaimPolicy**
   - `Retain` for production databases
   - `Delete` for ephemeral test data

2. **Set resource quotas for PVCs**
   ```yaml
   apiVersion: v1
   kind: ResourceQuota
   metadata:
     name: storage-quota
   spec:
     hard:
       requests.storage: "100Gi"
       persistentvolumeclaims: "10"
   ```

3. **Monitor storage usage**
   - Set up alerts for disk pressure
   - Monitor PVC usage with Prometheus

4. **Regular backups**
   - Use VolumeSnapshots if supported
   - External backup solutions (Velero)

5. **Test disaster recovery**
   - Practice restoring from backups
   - Document recovery procedures
