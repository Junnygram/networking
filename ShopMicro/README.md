# ShopMicro Production Platform

> This repository contains the complete infrastructure, containerization, and orchestration code to operate the ShopMicro e-commerce platform according to the Capstone Platform Engineering evaluation rubric.

---

## 1. Problem Statement & Architecture Summary
ShopMicro is a microservices-based e-commerce platform dependent on a distinct Frontend (React context logic), Backend API (Express), ML Service (Python), paired tightly with data stores (PostgreSQL & Redis). The goal is to provide a comprehensive, zero-trust, automated platform engineering solution for reproducible dev/staging/prod environments.

To operate systematically, we utilized:
- **Compute/Networking:** Kubernetes providing horizontal scaling, strict internal traffic restrictions, node affinity, taints/tolerations, and standard rollbacks capabilities.
- **Observability:** Prometheus, Grafana, & Custom application trace logic measuring precise SLIs mapping to latency and availability SLOs. 
- **Delivery/IaC:** GitHub Actions orchestrating Policy-as-Code checks, automated terraform plans detecting environment drift, alongside AWS Terraform Remote States, and Ansible mappings.

---

## 2. High-Level Architecture Diagram
```text
[ Internet Client ]
        | (HTTPS / Port 80)
        v
+------------------+     [ Cluster Ingress Namespace ]
| NGINX Ingress    | 
+------------------+
        | (Routing: /api -> backend, / -> frontend)
        v
======================================================
[ ShopMicro Kubernetes Namespace ]

    +-------------------+      +---------------------+
    |                   |      |                     |
    | frontend (React)  |<---->| ml-service (Flask)  |
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
*(All components reside within an AWS EKS/VPC managed by Terraform mapping modules)*

---

## 3. Prerequisites & Tooling Versions
*   **Docker:** v24.0+ (Required for local compose)
*   **Kubernetes:** v1.28+ (kubectl required)
*   **Terraform:** v1.5+ (Required for IaC structure execution)
*   **Make:** GNU Make (For simplified command logic)
*   **Python:** v3.12 (For ML Service development testing)
*   **Node.js:** v20 (For Express/React development testing)

---

## 4. Exact Deploy Commands
All deployment execution functions via `make`:

**Local Environment (Docker Compose):**
```bash
make build
make up
make logs
```

**Kubernetes Deployment (Make sure you have a valid context connected context):**
```bash
make k8s-apply 

# Expected output: Check status 
make k8s-status
```

---

## 5. Exact Test/Verification Commands
We provide a unified validation CLI utility script that verifies the health of the entire cluster landscape within the expected namespace, identifying CrashLoop logs, checking HPA, checking Ingress, and hitting internal APIs logic:

```bash
chmod +x ./scripts/devops.sh
./scripts/devops.sh
```

---

## 6. Observability Usage Guide
*   **Dashboards:** Import the corresponding JSON models under `observability/grafana-dashboards/` directly into your Grafana instance.
*   **Metrics:** Connect Grafana with Prometheus (Scraping configurations are in `observability/prometheus.yml`) targeting the Pods configured logic via our newly implemented `prom-client` within Express and `prometheus_client` in Flask.
*   **SLI/SLO Guide:** Review `observability/SLO_definitions.md` for our availability and latency rules (99.5% error-free capability with a p95 < 300ms logic). Actions > 5% trigger the specific alerts registered inside `alert-rules.yml`.

---

## 7. Rollback Procedure
If a recent deployment of `backend` introduced a regression, immediately trace back via replica history:
```bash
# 1. Inspect History
kubectl rollout history deployment/backend -n shopmicro

# 2. Undo the rollout back to the last stable state instantly
kubectl rollout undo deployment/backend -n shopmicro

# 3. Verify successful downgrade (Watch the Pods terminate and old versions recreate)
kubectl get pods -n shopmicro -w
```
Similarly for `frontend` or `ml-service`, replace the target name explicitly. 

---

## 8. Security Controls Implemented
1.  **Network Policies:** Least-privilege implemented (`k8s/network-policies.yaml`). Postgres and Redis strictly deny ingress unless from valid `backend` matching pod labels.
2.  **Secret Rotation Constraints:** Passwords mapped dynamically using Kubernetes `Secret` definitions ensuring no raw text variables hit config structures.
3.  **Taints/Tolerations & Affinity:** The Backend utilizes `podAntiAffinity` preventing single-node failures while the ML workload requires an `ml-workload: NoSchedule` exact match targeting appropriate node placements isolated from frontend execution flows.
4.  **Action Testing:** Conftest runs inside `.github/workflows/ci.yml` verifying policy conditions blocking regressions.
5.  **Disabled SSH:** As mandated by the `infrastructure/terraform/modules/security`, public networks strictly disable ingress outside of VPC local ranges.

---

## 9. Backup & Restore Procedure (PostgreSQL)
*   **Backup:** Stateful components leverage PVCs. The standard procedure runs an intra-cluster logical dump of the Postgres Stateful Set logic mapped to a secured S3 Bucket:
```bash
kubectl exec -it pg-data-postgres-0 -n shopmicro -- pg_dump -U postgres shopmicro > backup_db_dump.sql
aws s3 cp backup_db_dump.sql s3://shopmicro-db-backups/
```
*   **Restore:** 
```bash
aws s3 cp s3://shopmicro-db-backups/backup_db_dump.sql .
cat backup_db_dump.sql | kubectl exec -i pg-data-postgres-0 -n shopmicro -- psql -U postgres -d shopmicro 
```

---

## 10. Known Limitations & Next Improvements
1.  **Cert-Manager Integration:** Internal Ingress logic runs purely on HTTP mapping. Next iterations must include Let's Encrypt automated TLS structures for HTTPS resolution.
2.  **ArgoCD (GitOps):** Currently, workflows run traditional push-logic deployments. In standard environments promoting to Dev -> Staging -> Prod, implementing GitOps Pull-Deployments via ArgoCD is much safer.
3.  **Cross-Region Scaling:** Deployments are constrained to isolated topologies (`us-east-1a`). Extending data synchronizations into Multi-AZ DB replication improves absolute tier reliability.
