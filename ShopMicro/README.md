# ShopMicro Production Platform

> This repository contains the complete infrastructure, containerization, and orchestration code to operate the ShopMicro e-commerce platform according to the Capstone Platform Engineering evaluation rubric.

---

## 1. Problem Statement & Architecture Summary
ShopMicro is a microservices-based e-commerce platform dependent on a distinct Frontend (React context logic), Backend API (Express), ML Service (Python), paired tightly with data stores (PostgreSQL & Redis). The goal is to provide a comprehensive, zero-trust, automated platform engineering solution for reproducible dev/staging/prod environments.

To operate systematically, we utilized:
- **Compute/Networking:** Multi-node K3s cluster (v1.34) on AWS EC2 with horizontal scaling, strict internal traffic restrictions (Network Policies), and automated node provisioning via Terraform.
- **Observability:** Full stack monitoring (Prometheus, Grafana, Alertmanager) with **Slack Notifications** for critical system alerts (e.g., Service Down).
- **Delivery/IaC:** GitHub Actions orchestrating CI/CD with OIDC security, and **ArgoCD (GitOps)** with **Image Updater** for automated, push-free deployments.

---

## 2. High-Level Architecture Diagram
```text
[ Internet Client ]
        | (HTTP / Port 80)
        v
+------------------+     [ Cluster Ingress Namespace ]
| Traefik Ingress  | 
+------------------+
        | (Routing: /api -> backend, / -> frontend)
        v
======================================================
[ ShopMicro Kubernetes Namespace ]

    +-------------------+      +---------------------+
    |                   |      |                     |
    | frontend (React)  |<---->| ml-service (Python) |
    |                   |      |                     |
    +-------------------+      +---------------------+
            ^                             ^
            |                             | (Internal HTTP metrics)
            v                             v 
    +-------------------+                 |
    |                   |-----------------'
    | backend (Node.js) |
    |                   |
    +-------------------+
            ^      ^
            |      |
            v      v
+------------+    +-----------+
| PostgreSQL |    | Redis     |
+------------+    +-----------+
```

---

## 3. Platform Capabilities & Features (Finalized)
1.  **GitOps Deployment**: Automated sync between GitHub and Kubernetes via ArgoCD.
2.  **Automated Image Updates**: ArgoCD Image Updater polls ECR and triggers rollouts when a new `latest` tag is pushed.
3.  **Infrastructure as Code**: Terraform manages all AWS resources (VPC, ECR, EC2) with 20GB disk auto-resizing.
4.  **Security**: 
    - **OIDC Connection**: GitHub Actions uses IAM Roles for secure, keyless AWS access.
    - **Network Isolation**: Tight NetworkPolicies restricting cross-service traffic.
    - **Policy Enforcement**: Kyverno policies used for resource limit validation.
5.  **Smart Alerting**: Slack webhook integration sends alerts for High CPU, High Latency, or Service Outages.

---

## 4. Exact Deploy Commands
All deployment execution functions via `make`:

```bash
# 1. Build & Provision AWS Infra
make ev-02-tf-apply

# 2. Setup K3s Multi-node Cluster
make ev-03-fetch-kubeconfig
make k3s-join-worker

# 3. Deploy GitOps Controller (ArgoCD)
make ev-04-argocd-install
make ev-05-argocd-app

# 4. View Dashboard
make endpoints
```

---

## 5. Exact Test/Verification Commands
We provide a unified validation CLI utility script:
```bash
make ev-10-devops-script
```

**Alert Simulation (Slack Test):**
```bash
make alert-simulation
```

---

## 6. Observability & Monitoring
*   **Grafana Port:** 32300 (admin/admin)
*   **Prometheus Port:** 32090
*   **AlertManager Port:** 32093
*   **Slack Integration:** Alerts are sent to `#shopmicro-alerts` via Incoming Webhooks.

---

---

## 7. Deployment Evidence (Phase-by-Phase)

This section provides visual proof of the platform's capabilities, from initial provisioning to advanced chaos engineering.

### 🎥 Live Demo Recording
*   **Reliability & Self-Healing Suite**: Click below to view the video demonstration of Rollback, Canary Traffic Splitting, and Chaos Engineering.
*   **[Download/View reliability-demo.mov](evidence/Screenshots/reliability-demo.mov)**

### 📸 Phase 1: CI/CD & Foundation
![GitHub Actions Pipeline Success](evidence/Screenshots/Screenshot%202026-02-27%20at%2008.41.42.png)
*Pipeline status showing green builds and image pushes to ECR.*

![ECR Registry Status](evidence/Screenshots/Screenshot%202026-02-27%20at%2008.41.51.png)
*Container images successfully versioned and stored in AWS.*

### 📸 Phase 2: Infrastructure & Cluster
![Terraform Infrastructure Apply](evidence/Screenshots/Screenshot%202026-02-27%20at%2008.45.30.png)
*IaC completion for VPC, EC2 Nodes, and Security Groups.*

![K3s Multi-Node Cluster](evidence/Screenshots/Screenshot%202026-02-27%20at%2008.53.10.png)
*Verification of Master and Worker nodes in a Ready state.*

### 📸 Phase 3: GitOps & Applications
![ArgoCD Setup](evidence/Screenshots/Screenshot%202026-02-27%20at%2008.56.55.png)
*Initial ArgoCD configuration and repository connection.*

![ArgoCD Deployment UI](evidence/Screenshots/Screenshot%202026-02-27%20at%2008.57.03.png)
*ArgoCD managing the lifecycle of ShopMicro services.*

![Application Health Sync](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.31.30.png)
*All services (Backend, Frontend, ML) Synced and Healthy.*

![Microservice Pods Running](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.37.56.png)
*Workload distribution across the cluster namespace.*

![Ingress & Load Balancer](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.43.05.png)
*Public endpoints correctly mapped to internal cluster services.*

### 📸 Phase 4: Scaling & Security
![HPA Auto-scaling](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.43.20.png)
*Horizontal Pod Autoscaler configured for backend traffic spikes.*

![Network Policy Enforcement](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.45.16.png)
*Service-to-service restriction evidence.*

![DevOps Health Script](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.45.37.png)
*Automated validation of 10+ platform health checks.*

### 📸 Phase 5: Observability
![Prometheus UI](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.53.20.png)
*Prometheus server active and scraping cluster metrics.*

![Prometheus Targets](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.57.01.png)
*Discovery of all service endpoints for metric collection.*

![Grafana Performance Dashboard](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.57.17.png)
*Real-time visualization of cluster health and application SLOs.*

![AlertManager Status](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.57.27.png)
*Active alert routing configuration for critical incidents.*

![Metric Extraction](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.58.01.png)
*Raw metric data point extraction verification.*

![Logs Correlation](evidence/Screenshots/Screenshot%202026-02-27%20at%2009.58.16.png)
*Structured log aggregation for the distributed system.*

### 📸 Phase 6: Incident & Recovery
![Slack Alert Fired](evidence/Screenshots/Screenshot%202026-02-27%20at%2010.26.49.png)
*Real-world notification sent to the DevOps team during a service outage.*

![Rollback History](evidence/Screenshots/Screenshot%202026-02-27%20at%2010.36.15.png)
*Proof of zero-downtime recovery to a previous stable version.*

![Canary v1/v2 Split](evidence/Screenshots/Screenshot%202026-02-27%20at%2010.51.36.png)
*Progressive delivery evidence: Two versions running side-by-side.*

### 📸 Phase 7: Extra Credit (Chaos & FinOps)
![Chaos Engineering Recovery](evidence/Screenshots/Screenshot%202026-02-27%20at%2010.53.51.png)
*Self-healing test: Pods restored by K8s within seconds of failure.*

![Kyverno Policy Blocking](evidence/Screenshots/Screenshot%202026-02-27%20at%2010.54.12.png)
*Admission control: Blocking "bad" deployments that lack resource limits.*

![Cost Analysis Output](evidence/Screenshots/Screenshot%202026-02-27%20at%2010.54.39.png)
*FinOps: Resource utilization vs projected monthly infrastructure spend.*

---

---

## 10. Known Limitations & Next Improvements
1.  **Cert-Manager Integration:** Internal Ingress logic runs purely on HTTP. Future work should include automated TLS.
2.  **Stateful Backups**: Currently uses manual `pg_dump`. Production would use Velero for full cluster backup/restore.
3.  **Cross-Region Scaling:** Constrained to `us-east-1`. Extending to Multi-Region improves global latency and disaster recovery.
