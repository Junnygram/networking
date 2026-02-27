# 📋 Manual Steps During Demo

Keep this file open while running the evidence pipeline.

---

## ⚡ Before You Start (One-Time Setup)

### 1. Generate SSH Key
```bash
cd infrastructure/terraform
ssh-keygen -t rsa -b 4096 -f shopmicro-key -N ""
chmod 400 shopmicro-key
```

### 2. Create Slack Incoming Webhook
1. Go to https://api.slack.com/apps → Create New App → From Scratch
2. Name: `ShopMicro Alerts`, Workspace: your workspace
3. Click **Incoming Webhooks** → Activate
4. **Add New Webhook to Workspace** → select channel `#shopmicro-alerts`
5. Copy the webhook URL

### 3. Update AlertManager Slack Webhook
In `observability/manifests.yaml`, find:
```
api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
```
Replace with your real Slack webhook URL.

### 4. Set GitHub Secret
In your GitHub repo → Settings → Secrets → Actions:
- `GH_ACTIONS_ROLE_ARN` = output from `terraform output github_actions_role_arn`

### 5. Push Code to Trigger Pipeline
After `ev-02` (terraform creates ECR + OIDC), push code to `main`:
```bash
git add -A && git commit -m "feat: full capstone setup" && git push origin main
```
This triggers the CI pipeline which builds and pushes Docker images to ECR.
Trigger it 2-3 times by making small changes (e.g., add a comment in backend/server.js)
to create multiple image tags for rollback evidence.

---

## 🎬 Evidence Collection — 20 Screenshots

### PHASE 0: CI Pipeline
| # | Command | Screenshot |
|---|---------|------------|
| 1 | `make ev-01-ci-pipeline` | **GitHub Actions**: all jobs green ✓ |

### PHASE 1: Infrastructure
| # | Command | Screenshot |
|---|---------|------------|
| 2 | `make ev-02-tf-apply` | Terminal: "Apply complete!" with ECR + EC2 |
| 3 | `make ev-03-fetch-kubeconfig` | Terminal: nodes Ready |

### PHASE 2: ArgoCD + GitOps
| # | Command | Screenshot |
|---|---------|------------|
| 4 | `make ev-04-argocd-install` | Terminal: ArgoCD pods running |
| 5 | `make ev-05-argocd-app` | **Browser**: ArgoCD app synced (see manual steps below) |

### PHASE 3: Applications
| # | Command | Screenshot |
|---|---------|------------|
| 6 | `make ev-06-pods` | Terminal: pods Running |
| 7 | `make ev-07-services` | Terminal: services + ingress |
| 8 | `make ev-08-hpa` | Terminal: HPA config |
| 9 | `make ev-09-netpol` | Terminal: network policies |
| 10 | `make ev-10-devops-script` | Terminal: health check + evidence/ files |

### PHASE 4: Observability
| # | Command | Screenshot |
|---|---------|------------|
| 11 | `make ev-11-monitoring-deploy` | Terminal: monitoring pods Running |
| 12 | `make ev-12-prometheus` | **Browser**: Prometheus Targets + Alerts |
| 13 | `make ev-13-grafana` | **Browser**: Grafana dashboards (see manual steps) |
| 14 | `make ev-14-alertmanager` | **Browser**: AlertManager Status showing Slack |

### PHASE 5: Incident & Recovery
| # | Command | Screenshot |
|---|---------|------------|
| 15 | `make ev-15-slack-alert` | **Slack**: alert in #shopmicro-alerts |
| 16 | `make ev-16-rollback` | Terminal: rollback success + revision history |

### PHASE 6: Extra Credit
| # | Command | Screenshot |
|---|---------|------------|
| 17 | `make ev-17-canary` | Terminal: v1 + v2 deployments + canary ingress |
| 18 | `make ev-18-chaos` | Terminal: pod kill + Redis failure |
| 19 | `make ev-19-policies` | Terminal: Kyverno policies + blocked pod |
| 20 | `make ev-20-cost` | Terminal: cost analysis from costs.md |

---

## 📝 Manual Steps During Specific Targets

### During ev-04 (ArgoCD Install):
Run port-forward in a separate terminal:
```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443 &
```

### During ev-05 (ArgoCD App — BROWSER):
1. Open: `https://localhost:8443`
2. Login: `admin` / (password from ev-04 output)
3. Click **+ New App**:
   - Name: `shopmicro`
   - Project: `default`
   - Repo URL: `https://github.com/Junnygram/networking.git`
   - Path: `ShopMicro/k8s`
   - Cluster: `https://kubernetes.default.svc`
   - Namespace: `shopmicro`
4. Click **Create** → **Sync**
5. 📸 Screenshot the synced view showing resources + ECR images

### During ev-13 (Grafana — BROWSER):
1. Login: `admin` / `admin`
2. **Connections → Data Sources → Add Prometheus**
3. URL: `http://prometheus.monitoring.svc.cluster.local:9090`
4. Click **Save & Test** (green ✓)
5. **Dashboards → Import** → Upload each JSON from `observability/grafana-dashboards/`
6. 📸 Screenshot each dashboard

### During ev-15 (Slack Alert):
1. Pod is deleted by the make target
2. Wait ~2 minutes
3. Open Slack → `#shopmicro-alerts`
4. 📸 Screenshot the alert notification

### During ev-19 (Kyverno Policies):
After policies are applied, try this to show enforcement:
```bash
kubectl run test-bad --image=nginx -n shopmicro
# Should be BLOCKED: "CPU and memory limits are required"
```
📸 Screenshot the blocked attempt

---

## 🧹 Cleanup
```bash
make tf-destroy
```

---

## 📌 Key Notes
- AWS creds and KUBECONFIG are auto-set in the Makefile — no manual export needed
- SSH key must exist at `infrastructure/terraform/shopmicro-key` before `ev-02`
- Wait ~120s after `ev-02` before `ev-03` (K3s install time)
- Slack webhook must be real for `ev-15` to work
- Push code to `main` at least 2-3 times to get multiple pipeline runs/revisions
- `tf-destroy` handles its own `terraform init` so it works from any state
