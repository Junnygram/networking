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

## 10. Known Limitations & Next Improvements
1.  **Cert-Manager Integration:** Internal Ingress logic runs purely on HTTP. Future work should include automated TLS.
2.  **Stateful Backups**: Currently uses manual `pg_dump`. Production would use Velero for full cluster backup/restore.
3.  **Cross-Region Scaling:** Constrained to `us-east-1`. Extending to Multi-Region improves global latency and disaster recovery.
