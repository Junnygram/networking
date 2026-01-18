# Kubernetes Practical Assignment: E-Commerce Platform Deployment

## Part 1: Cluster Setup and Node Labeling (30 minutes)
- [x] **Task 1.1: Install Kubernetes Cluster**
    - Set up a 3-node Kubernetes cluster on AWS (1 Control Plane, 2 Workers).
    - [x] provisioning infrastructure (Terraform/EC2)
    - [x] Verify nodes: `kubectl get nodes` (Expected: 1 control-plane, 2 workers)
- [x] **Task 1.2: Label Your Nodes**
    - [x] `worker-node-1`: `environment=production`, `storage=ssd`, `tier=frontend`
    - [x] `worker-node-2`: `environment=production`, `storage=hdd`, `tier=backend`
    - [x] Verify: `kubectl get nodes --show-labels`
- [x] **Task 1.3: Apply Taints to Nodes**
    - [x] `worker-node-1`: `workload=frontend:NoSchedule`
    - [x] `worker-node-2`: `workload=backend:NoSchedule`
    - [x] Verify: `kubectl describe node <node> | grep -i taint`

## Part 2: Deploy the Database Layer (45 minutes)
- [x] **Task 2.1: Create a Namespace**
    - [x] Create namespace `ecommerce`
    - [x] Set context default: `kubectl config set-context --current --namespace=ecommerce`
- [x] **Task 2.2: Deploy PostgreSQL Database**
    - [x] Create `postgres-deployment.yaml`
        - Image: `postgres:16`
        - Env: `POSTGRES_PASSWORD=secure_password`
        - Node Selector: Backend tier
        - Toleration: Backend taint
        - Resources: Requests (500m/512Mi), Limits (1000m/1Gi)
        - Replicas: 1
        - Port: 5432
- [x] **Task 2.3: Create a Service for PostgreSQL**
    - [x] Create `postgres-service.yaml` (ClusterIP, Port 5432, Selector `app=postgres`)
- [x] **Task 2.4: Verify Database Deployment**
    - [x] Apply manifests
    - [x] Verify pods (`kubectl get pods -o wide`)
    - [x] Answer Question 1: Node scheduling location?
    - [x] Answer Question 2: Removal of toleration effect?
    - [x] Answer Question 3: External access?

## Part 3: Deploy Redis Cache with Affinity Rules (45 minutes)
- [x] **Task 3.1: Deploy Redis**
    - [x] Create `redis-deployment.yaml`
        - Image: `redis:7-alpine`
        - Replicas: 2
        - Pod Anti-Affinity: Ensure replicas run on different nodes (`topologyKey: "kubernetes.io/hostname"`)
        - Tolerations: Run on both frontend and backend nodes
        - Resources: Requests (250m/256Mi)
        - Port: 6379
- [x] **Task 3.2: Create Redis Service**
    - [x] Create `redis-service.yaml` (ClusterIP, Port 6379, Selector `app=redis`)
- [x] **Task 3.3: Verify Redis Deployment**
    - [x] Apply manifests
    - [x] Check node distribution
    - [x] Answer Question 1: Are pods on different nodes?
    - [x] Answer Question 2: Scaling to 3 replicas with 2 nodes?
    - [x] Answer Question 3: `preferredDuringScheduling` vs `required`?

## Part 4: Deploy Backend API with Node Affinity (60 minutes)
- [x] **Task 4.1: Deploy Backend API**
    - [x] Create `backend-deployment.yaml`
        - Image: `nginx:alpine` (placeholder)
        - Replicas: 3
        - Node Affinity: Prefer SSD, Require Backend tier
        - Toleration: Backend workload
        - Resources: Requests (200m/256Mi)
        - Port: 80
        - Env: `DATABASE_HOST=postgres`, `REDIS_HOST=redis`
- [x] **Task 4.2: Create Backend Service**
    - [x] Create `backend-service.yaml` (ClusterIP, Port 8080 -> Target 80)
- [x] **Task 4.3: Test Backend Connectivity**
    - [x] Create test pod (`curlimages/curl`)
    - [x] Test `curl http://backend:8080`, `nslookup postgres`, `nslookup redis`
    - [x] Answer Question 1: Node scheduling?
    - [x] Answer Question 2: Affinity types difference?
    - [x] Answer Question 3: Connectivity demonstration?

## Part 5: Deploy Frontend with Multiple Replicas (45 minutes)
- [x] **Task 5.1: Deploy Frontend Application**
    - [x] Create `frontend-deployment.yaml`
        - Image: `nginx:alpine`
        - Replicas: 4
        - Node Selector: Frontend tier
        - Toleration: Frontend workload
        - Resources: Requests (100m/128Mi)
        - Port: 80
        - Env: `BACKEND_URL=http://backend:8080`
- [x] **Task 5.2: Create Frontend Service**
    - [x] Create `frontend-service.yaml` (NodePort, Port 80, NodePort 30080)
- [x] **Task 5.3: Test Frontend Access**
    - [x] Curl `http://<NODE_IP>:30080`
- [x] **Task 5.4: Scale the Frontend**
    - [x] Scale to 6 replicas
    - [x] Answer Question 1: Scheduling locations?
    - [x] Answer Question 2: Scale to 10 on single node?
    - [x] Answer Question 3: NodePort distribution?
    - [x] Answer Question 4: Browser access?

## Part 6: Create Static Pods for Monitoring (45 minutes)
- [x] **Task 6.2: Create a Monitoring Agent Static Pod**
    - [x] SSH into `worker-node-1`
    - [x] Identify static pod path (usually `/etc/kubernetes/manifests`)
    - [x] Create `monitoring-agent.yaml` in that path
- [x] **Task 6.3: Verify Static Pod**
    - [x] Check on control plane: `kubectl get pods -n kube-system`
- [x] **Task 6.4: Try to Delete the Static Pod**
    - [x] Attempt delete via kubectl
    - [x] Answer Question 1: What happens on delete?
    - [x] Answer Question 2: How to actually remove?
    - [x] Answer Question 3: Visibility in `get pods -A`?
    - [x] Answer Question 4: Use cases?

## Part 7: Troubleshooting and Recovery (60 minutes)
- [x] **Task 7.1: Simulate Node Failure**
    - [x] Drain `worker-node-1`
    - [x] Observe rescheduling
    - [x] Answer Question 1: What happened to pods?
    - [x] Answer Question 2: Did all reschedule?
    - [x] Answer Question 3: Static pod behavior?
- [x] **Task 7.2: Bring Node Back Online**
    - [x] Uncordon `worker-node-1`
- [x] **Task 7.3: Debug a Broken Deployment**
    - [x] Create `broken-app.yaml` (intentionally bad config)
    - [x] Investigate issues (`describe pod`)
    - [x] Fix the deployment
    - [x] Answer Question 1: Why not scheduling?
    - [x] Answer Question 2: Commands used?
    - [x] Answer Question 3: How fixed?

## Part 8: Advanced Scheduling Scenarios (60 minutes)
- [x] **Task 8.1: Implement Pod Priority**
    - [x] Create PriorityClasses (`high-priority`, `low-priority`)
- [x] **Task 8.2: Deploy with Different Priorities**
    - [x] Update frontend to `high-priority`
    - [x] Create `batch-job-deployment.yaml` with `low-priority`
- [x] **Task 8.3: Resource Pressure Test**
    - [x] Scale up batch processor
    - [x] Scale up frontend
    - [x] Observe preemption
    - [x] Answer Question 1: High-priority resource needs?
    - [x] Answer Question 2: Eviction order?
    - [x] Answer Question 3: Priority effect?

## Part 9: Comprehensive Testing (45 minutes)
- [x] **Task 9.1: Create a Test Plan**
- [x] **Task 9.2: Execute Tests**
    - [x] Service Discovery
    - [x] Load Balancing
    - [x] Self-Healing
    - [x] Scaling
- [x] **Task 9.3: Document Results**
    - [x] Create test report

## Part 10: Cleanup and Documentation (30 minutes)
- [x] **Task 10.1: Create Architecture Diagram**
- [x] **Task 10.2: Document Your Setup (DEPLOYMENT.md)**
- [x] **Task 10.3: Cleanup (Optional)**

## Deliverables Checklist
- [x] `postgres-deployment.yaml` & service
- [x] `redis-deployment.yaml` & service
- [x] `backend-deployment.yaml` & service
- [x] `frontend-deployment.yaml` & service
- [x] `monitoring-agent.yaml`
- [x] `broken-app.yaml` (fixed)
- [x] Priority classes
- [x] `batch-job-deployment.yaml`
- [x] `DEPLOYMENT.md`
- [x] `ANSWERS.md` (with answers to all questions)
- [x] Test report
- [x] Architecture diagram
- [x] Screenshots (15+)
