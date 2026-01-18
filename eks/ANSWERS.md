# Assignment Answers

## Part 2: Deploy the Database Layer

### 1. On which node did the postgres pod get scheduled? Why?
The Postgres pod was scheduled on node `<WORKER_NODE_2_NAME>` (Worker Node 2).
**Why:**
1.  **Node Selector:** The deployment specifies `nodeSelector: tier: backend`. Node `<WORKER_NODE_2_NAME>` is labeled with `tier=backend`.
2.  **Tolerations:** The node has a taint `workload=backend:NoSchedule`. The deployment includes a matching toleration, allowing it to be scheduled there despite the taint.

### 2. What happens if you remove the toleration? Test it and explain.
If the toleration is removed, the pod will fail to schedule and remain in a **Pending** state.
**Explanation:** The node `<WORKER_NODE_2_NAME>` has a taint `workload=backend:NoSchedule`. Kubernetes scheduler will filter out this node because the pod does not tolerate the taint. Since this is the only node that satisfies the `nodeSelector` (tier=backend), there are no valid nodes available for the pod.

### 3. Can you access the database from outside the cluster? Why or why not?
**No**, you cannot access it from outside the cluster.
**Reason:** The service is defined as `type: ClusterIP`. This creates a stable internal IP address meant only for communication between pods within the cluster. It does not expose a port on the node's external IP (NodePort) or provision an external Load Balancer.

## Part 3: Deploy Redis Cache with Affinity Rules

### 1. Are the Redis pods running on different nodes? Why?
**Yes**, the Redis pods are running on different nodes.
**Why:** The deployment includes a **Pod Anti-Affinity** rule with `requiredDuringSchedulingIgnoredDuringExecution`. It uses the `topologyKey: "kubernetes.io/hostname"`, which mandates that no two pods with the label `app=redis` can be scheduled on the same node (hostname).

### 2. What would happen if you tried to scale to 3 replicas but only have 2 worker nodes?
If you only had 2 worker nodes, the 3rd replica would remain in a **Pending** status.
**Reason:** The `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity rule is a hard constraint. Since the first two pods would occupy the two available unique hostnames, the scheduler would find no remaining nodes that satisfy the condition of "not having an `app=redis` pod already".

### 3. Change the anti-affinity rule to preferredDuringSchedulingIgnoredDuringExecution. What's the difference?
**Difference:** `preferredDuringScheduling...` is a **soft constraint**.
If changed to "preferred", the scheduler would *try* to place pods on different nodes to satisfy the preference. However, if no unique nodes were available (e.g., scaling to 3 replicas on 2 nodes), the scheduler **would** allow the 3rd pod to be scheduled on a node that already hosts a Redis pod, ensuring high availability (running pods) over strict separation.

## Part 4: Deploy Backend API with Node Affinity

### 1. On which node(s) are the backend pods scheduled? Why?
The backend pods are scheduled on node `<WORKER_NODE_2_NAME>` (Worker Node 2).
**Why:**
-   **Required Affinity:** The deployment enforces `requiredDuringSchedulingIgnoredDuringExecution` for `tier: backend`. Only Worker Node 2 matches this label.
-   **Preferred Affinity:** The deployment prefers `storage: ssd`. However, Worker Node 2 has `storage: hdd`.
-   **Result:** The "Required" rule acts as a strict filter. Worker Node 1 has SSDs but is `tier: frontend`, so it is filtered out. The scheduler is forced to pick Worker Node 2 despite it not matching the creation preference (SSD).

### 2. What's the difference between requiredDuringScheduling and preferredDuringScheduling?
-   **requiredDuringScheduling...** (Hard Affinity): The scheduler **must** satisfy this rule. If no node matches the criteria, the pod will not be scheduled and will stay Pending.
-   **preferredDuringScheduling...** (Soft Affinity): The scheduler **tries** to satisfy this rule. If a matching node is found, it is prioritized (weighted). If no matching node is found, the scheduler will still schedule the pod on any other valid node.

### 3. Can the backend pods communicate with postgres and redis? Demonstrate.
**Yes.**
-   **DNS Resolution:** Pods in the same namespace can resolve services by name (`postgres`, `redis`).
-   **Connectivity:** Since we are using ClusterIP services, standard pod-to-pod communication works across nodes (handled by CNI/Kube-proxy).
-   *Demonstration would typically involve running `curl http://backend:8080`, `nslookup postgres`, etc. from a test pod.*

## Part 5: Deploy Frontend with Multiple Replicas

### 1. Where are all the frontend pods scheduled? Why?
All frontend pods are scheduled on node `<WORKER_NODE_1_NAME>` (Worker Node 1).
**Why:** The deployment uses a **Node Selector** matching `tier: frontend`. Since only Worker Node 1 has this label, the scheduler forces all frontend pods onto this single node.

### 2. What happens if you try to scale to 10 replicas on a single node?
It depends on the node's available resources.
-   **Resource Calculation:** Each pod requests 100m CPU. 10 replicas = 1000m (1 vCPU).
-   **Outcome:** A `t3.medium` instance has 2 vCPUs. Assuming the node isn't heavily loaded by other system processes, **all 10 replicas will likely schedule successfully**.
-   **Failure Scenario:** If the node ran out of CPU or Memory (e.g., if we scaled to 25+ replicas or if other pods were consuming resources), the scheduler would fail to place the new pods, and they would remain in a **Pending** state with a "Insufficient cpu" or "Insufficient memory" event.

### 3. How does the NodePort service distribute traffic across replicas?
The NodePort service uses the cluster's internal load balancing mechanism (implemented by **kube-proxy**).
-   When traffic hits `<NodeIP>:30080`, kube-proxy intercepts it.
-   It distributes the traffic to one of the available backing pods (endpoints) for the frontend service.
-   The distribution strategy is typically **random** (iptables mode) or round-robin, ensuring traffic is spread across the 6 replicas.

### 4. Access the application from your browser. Does it work?
**Yes.** Accessing `http://<Worker-Node-IP>:30080` loads the Nginx default page (or the application if we deployed the actual source). The NodePort exposes the service on every node's IP at port 30080.

## Part 6: Create Static Pods for Monitoring

### 1. What happens when you try to delete a static pod? Why?
If you try to delete the static pod via `kubectl`, it will **immediately be recreated**.
**Why:** Static pods are managed directly by the **Kubelet** on the node, not by the Kubernetes API server (Deployment/ReplicaSet controller). The Kubelet watches the `/etc/kubernetes/manifests` directory. As long as the manifest file exists there, the Kubelet ensures the pod is running. When you delete it via API, Kubelet sees the file is still there and restarts it.

### 2. How would you actually remove a static pod?
You must **delete the manifest file** from the node's filesystem.
Running `rm /etc/kubernetes/manifests/monitoring-agent.yaml` on the node will cause the Kubelet to terminate the pod.

### 3. Where does the static pod show up when you run kubectl get pods -A?
It shows up in the namespace defined in the manifest (in our case, `kube-system`). The name is typically suffixed with the node name (e.g., `monitoring-agent-worker-node-1`).

### 4. What are the use cases for static pods?
-   **Control Plane Components:** Running valid components like `etcd`, `kube-apiserver`, `kube-controller-manager`, and `kube-scheduler` (in kubeadm clusters).
-   **Node-specific Daemons:** Running agents that must be present on a specific node for bootstrapping or hardware management before the full cluster is available.

## Part 7: Troubleshooting and Recovery

### 1. What happened to the pods running on worker-node-1?
When the node was drained:
-   **Eviction:** Controlled pods (part of Deployments/ReplicaSets) were evicted (terminated).
-   **Rescheduling:** The scheduler attempted to recreate them on other available nodes.

### 2. Did all pods get rescheduled? Which ones didn't and why?
**No**, not all pods rescheduled.
-   **Frontend Pods:** Since they have a strict `nodeSelector` for `tier: frontend`, and Worker Node 1 is the *only* node with that label, the evicted pods entered a **Pending** state. They cannot be scheduled on the backend node.
-   **Redis Pods:** One Redis replica was on Node 1. It was evicted and successfully rescheduled to Node 2 (Backend) because it had tolerations for the backend taint and satisfied the anti-affinity rule (Node 2 != Node hosting the other Redis replica).

### 3. What happened to the static pod?
The static pod **remained running**.
`kubectl drain` tries to delete the mirror pod API object, but since the Kubelet on the node is still running and the manifest file is still present, the Kubelet ignores the API deletion or restarts the pod immediately. Static pods are not subject to standard eviction rules.

### Debugging Broken Deployment
1.  **Why aren't the pods scheduling?**
    The pods requested `cpu: 5000m` (5 vCPUs). The worker nodes (`t3.medium`) only have 2 vCPUs. The request exceeded the allocatable capacity of any single node, so the scheduler could not find a fit.
2.  **What kubectl commands did you use to diagnose the issue?**
    -   `kubectl get pods` (Showed Pending status)
    -   `kubectl describe pod <pod-name>` (Showed "Insufficient cpu" event)
3.  **How did you fix it?**
    I edited the deployment manifest to reduce the CPU request to a reasonable value (e.g., `50m`), allowing the pods to fit on the nodes.

## Part 8: Advanced Scheduling Scenarios

### 1. What happens when high-priority pods need resources?
If a high-priority pod cannot be scheduled due to insufficient resources, the scheduler initiates **preemption**. It searches for a node where evicting one or more lower-priority pods would make enough space for the high-priority pod.

### 2. Which pods get evicted first?
Pods with **lower PriorityClass values** are candidates for eviction. In our scenario, pods with `priorityClassName: low-priority` (value 100) or default priority (0) would be evicted to make room for `high-priority` (value 1000) pods.

### 3. How does priority affect scheduling decisions?
-   **Scheduling Order:** Pending pods with higher priority are placed at the front of the scheduling queue.
-   **Preemption:** If no nodes are available, the scheduler evicts lower-priority pods to create space for higher-priority ones.
-   **Stability:** Priorities help ensure that critical workloads (like Frontend/Payment payments) stay running even during resource crunch, at the expense of non-critical workloads (like Batch jobs).


`

## Deliverables & Proof

1.  **Screenshots (Already Captured):**
    -   `images/1.png`
    -   `images/2.png`
    -   `images/3.png`
    -   `images/4.png`
    -   `images/5.png`
2.  **Files:** Ensure you have the following files ready for submission:
    -   `COMMANDS.md`
    -   `ANSWERS.md`
    -   `DEPLOYMENT.md`
    -   `manifests/` directory
    -   `images/` directory containing the screenshots above.