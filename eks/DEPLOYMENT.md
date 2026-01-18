# E-Commerce Platform Deployment Documentation

## Cluster Architecture
The Kubernetes cluster is deployed on AWS EC2 instances using `kubeadm` and Terraform.
-   **Control Plane:** 1 Node (t3.medium)
-   **Worker Nodes:** 3 Nodes (t3.medium)
    -   `worker-node-1` (ip-10-0-102-148): Labeled `tier=frontend`, `storage=ssd`. Tainted `workload=frontend:NoSchedule`.
    -   `worker-node-2` (ip-10-0-102-152): Labeled `tier=backend`, `storage=hdd`. Tainted `workload=backend:NoSchedule`.
    -   `worker-node-3` (ip-10-0-103-185): Unlabeled/Untainted (General purpose).

## Scheduling Decisions
### 1. Database Layer (Postgres)
-   **Placement:** Restricted to `tier: backend` using Node Selector.
-   **Isolation:** Tolerates `backend` taint to ensure dedicated resources.

### 2. Cache Layer (Redis)
-   **High Availability:** Enforced using `podAntiAffinity` (Required) to ensure replicas run on distinct nodes.
-   **Reachability:** Tolerates both frontend and backend taints to maximize placement options across the cluster.

### 3. Backend API
-   **Requirements:** MUST run on `tier: backend` nodes (Hard affinity).
-   **Preferences:** PREFERS `storage: ssd`, but since the backend node has HDD, the hard requirement overrides the soft preference.

### 4. Frontend
-   **Placement:** Pinned to `tier: frontend` node.
-   **Access:** Exposed via NodePort (30080) for external access.

## Priority & Quality of Service
-   **High Priority:** Frontend application (User-facing).
-   **Low Priority:** Batch processing jobs.
-   **Mechanism:** PriorityClasses ensure that if the cluster runs out of resources, batch jobs are preempted to keep the frontend running.

## Challenges & Solutions
1.  **Node Maintenance:** Draining a node correctly evicts managed pods but leaves static pods running (as expected).
2.  **Resource Limits:** Misconfigured deployments (5000m CPU) caused pending pods. Diagnosed via `kubectl describe` and fixed by right-sizing requests.
3.  **Affinity Conflicts:** Understanding why a pod didn't schedule on an SSD node despite preference (due to a stricter hard requirement on 'tier') was key.

## Deployment Instructions
1.  **Infrastructure:** Run `terraform apply` in the `eks` directory.
2.  **Manifests:** Copy `manifests/` to master node.
3.  **Apply:**
    ```bash
    kubectl apply -f manifests/namespace.yaml
    kubectl apply -f manifests/postgres/
    kubectl apply -f manifests/redis/
    kubectl apply -f manifests/backend/
    kubectl apply -f manifests/frontend/
    ```
