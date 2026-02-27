# 🎬 ShopMicro Capstone Demo Runbook

Follow this EXACTLY step by step. No skipping. No improvising.

---

## ⚡ BEFORE YOU START (do this once, before anything else)

### Step 0A: SSH Key Check
All commands can now be run directly from the **root** folder (`/networking`).
Check if your SSH key exists:
```bash
ls -l ShopMicro/infrastructure/terraform/shopmicro-key
```
If it doesn't exist, run this (otherwise skip):
```bash
ssh-keygen -t rsa -b 4096 -f ShopMicro/infrastructure/terraform/shopmicro-key -N ""
chmod 400 ShopMicro/infrastructure/terraform/shopmicro-key
```

### Step 0B: Create Slack Webhook
1. Go to https://api.slack.com/apps
2. Click **Create New App** → **From Scratch**
3. Name: `ShopMicro Alerts`, pick your workspace
4. Left sidebar → **Incoming Webhooks** → Toggle ON
5. Click **Add New Webhook to Workspace**
6. Pick channel: `#shopmicro-alerts` (create it first if needed)
7. Copy the webhook URL (starts with `https://hooks.slack.com/services/...`)

### Step 0C: Paste Slack Webhook into Config
Open `observability/manifests.yaml`, find this line (~line 100):
```
api_url: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK'
```
Replace it with your REAL Slack webhook URL. Save the file.

### Step 0D: Make sure devops.sh is executable
```bash
chmod +x scripts/devops.sh
```

---

## 🚀 PHASE 1: INFRASTRUCTURE (Terraform)

### Step 1: Terraform Apply
```bash
make ev-02-tf-apply
```
**Wait for it to finish.** It takes ~3 minutes.

**When it's done you'll see:**
- `Apply complete! Resources: X added`
- ECR repository URLs printed
- GitHub Actions Role ARN printed

**📸 SCREENSHOT [2/20]:** The terminal showing "Apply complete!" with the outputs.

**⚠️ IMPORTANT — Copy the Role ARN that was printed.** You need it for the next step.

### Step 2: Add GitHub Secret
1. Go to https://github.com/Junnygram/networking/settings/secrets/actions
2. Click **New repository secret**
3. Name: `GH_ACTIONS_ROLE_ARN`
4. Value: paste the ARN from Step 1 output
5. Click **Add secret**

### Step 3: Push Code to Trigger Pipeline
```bash
make push-trigger
```
This does `git add` → `commit` → `push` automatically.

**After push succeeds:**
- Go to GitHub → **Actions** tab
- Watch the pipeline run
- **While waiting** for pipeline, K3s is installing on your EC2 — do NOT rush to Step 4
- **Wait at least 2 minutes** before Step 4

**📸 SCREENSHOT [1/20]:** GitHub Actions showing all jobs with green ✓ checks.

### Step 4: Fetch Kubeconfig + Show Nodes
```bash
make ev-03-fetch-kubeconfig
```
**Wait time is built in (120s).** Just let it run.

**📸 SCREENSHOT [3/20]:** Terminal showing nodes in `Ready` state.

---

## 🔄 PHASE 2: ARGOCD (GitOps)

### Step 5: Install ArgoCD + Image Updater
```bash
make ev-04-argocd-install
```
**Wait time is built in (60s).** It prints the admin password at the end.

**⚠️ Copy the admin password printed at the bottom.**

**📸 SCREENSHOT [4/20]:** Terminal showing ArgoCD pods running.

### Step 6: Open ArgoCD UI
You can now access ArgoCD **directly** without port-forwarding.
From the **root** directory, run:
```bash
make argocd-pf
```
It will print the password and your **direct URL** (which uses Port 30080).

Type that URL into your browser (e.g., `http://98.94.43.109:30080`).

Now open browser: **http://<MASTER_IP>:30080**
- Login: `admin` / (password from Step 5)

### Step 7: Create ArgoCD Application (CLI)
From the **root** folder, run:
```bash
make ev-05-argocd-app
```
**This will automatically:**
1. Apply the Application manifest to your cluster.
2. Set up the repo, project, and path.
3. Configure the **Image Updater** for ECR.
4. Trigger an immediate Sync.

**📸 SCREENSHOT [5/20]:**
Go back to your ArgoCD tab in the browser. You will see the `shopmicro` application appear and turn **Healthy/Synced**. Click it to show all the green resources.

---

> [!TIP]
> **Manual Alternative (if CLI fails):**
> 1. Click **+ New App** → Application Name: `shopmicro`, Project: `default`, Sync: `Manual`.
> 2. Repo: `https://github.com/Junnygram/networking.git`, Path: `ShopMicro/k8s`.
> 3. Cluster: `https://kubernetes.default.svc`, Namespace: `shopmicro`.

---

## 📦 PHASE 3: APPLICATIONS

### Step 8: Show Pods
```bash
make ev-06-pods
```
**📸 SCREENSHOT [6/20]:** Terminal showing all pods in **Running** state.

### Step 9: Show Services + Ingress
```bash
make ev-07-services
```
**📸 SCREENSHOT [7/20]:** Terminal showing ClusterIP services + Ingress.

### Step 10: Show HPA
```bash
make ev-08-hpa
```
**📸 SCREENSHOT [8/20]:** Terminal showing HPA with CPU target and replica counts.

### Step 11: Show Network Policies
```bash
make ev-09-netpol
```
**📸 SCREENSHOT [9/20]:** Terminal showing network policies (default-deny, frontend, backend, postgres, redis).

### Step 12: Run DevOps Script
```bash
make ev-10-devops-script
```
**📸 SCREENSHOT [10/20]:** Terminal showing health check output + evidence/ files listed.

---

## 📊 PHASE 4: OBSERVABILITY

### Step 13: Deploy Monitoring Stack
```bash
make ev-11-monitoring-deploy
```
**Wait time is built in (30s).**

**📸 SCREENSHOT [11/20]:** Terminal showing prometheus, grafana, alertmanager pods all `Running`.

**If alertmanager shows CrashLoopBackOff:**
You forgot to update the Slack webhook URL (Step 0C). Fix it, then run the deploy again:
```bash
make ev-11-monitoring-deploy
```

### Step 14: Prometheus (Browser)
```bash
make ev-12-prometheus
```
It prints a URL like `http://<IP>:32090`. Open it in your browser.
- Click **Status** → **Targets**
- **📸 SCREENSHOT [12/20]:** Prometheus Targets page.
- Click **Alerts**
- **📸 BONUS:** Prometheus Alerts page showing the rules.

### Step 15: Grafana (Browser)
```bash
make ev-13-grafana
```
It prints a URL like `http://<IP>:32300`. Open it in your browser.

1. Login: `admin` / `admin` (skip change password)
2. Go to **Connections** → **Data Sources** → **Add data source**
3. Select **Prometheus**
4. URL: `http://prometheus.monitoring.svc.cluster.local:9090`
5. Scroll down → **Save & Test** → should show green ✓
6. Go to **Dashboards** → **New** → **Import**
7. Click **Upload dashboard JSON file**
8. Upload files from `observability/grafana-dashboards/` one by one
9. For each, select your Prometheus data source, then Import

**📸 SCREENSHOT [13/20]:** A Grafana dashboard showing panels with data.

### Step 16: AlertManager (Browser)
```bash
make ev-14-alertmanager
```
It prints a URL like `http://<IP>:32093`. Open it in your browser.
- Click **Status** in the top menu

**📸 SCREENSHOT [14/20]:** AlertManager status page showing the Slack receiver config.

---

## 🚨 PHASE 5: INCIDENT & RECOVERY

### Step 17: Slack Alert — Kill a Pod
```bash
make ev-15-slack-alert
```
This deletes a backend pod. Then:
1. Watch pods recover: `kubectl get pods -n shopmicro -w` (in separate tab)
2. Wait ~2 minutes for Prometheus to detect → fire alert → Slack
3. Open Slack → `#shopmicro-alerts`

**📸 SCREENSHOT [15/20]:** The Slack alert notification message.

**If alert doesn't fire:** Check AlertManager UI → Alerts tab. The alert rules have a `for: 2m` / `for: 5m` delay.

### Step 18: Rollback
```bash
make ev-16-rollback
```
This creates a bad revision (sets env var), then rolls it back.

**📸 SCREENSHOT [16/20]:** Terminal showing "rolled back" + revision history.

---

## ⭐ PHASE 6: EXTRA CREDIT

### Step 19: Canary Deployment
```bash
make ev-17-canary
```
**📸 SCREENSHOT [17/20]:** Terminal showing v1 + v2 deployments + canary ingress with 20% weight.

### Step 20: Chaos Experiments
```bash
make ev-18-chaos
```
**⏱ Start a timer when it runs!** You need MTTD (time to detect) and MTTR (time to recover).

**📸 SCREENSHOT [18/20]:** Terminal showing pod killed + Redis scaled to 0.

**After screenshot, restore Redis:**
```bash
kubectl scale deployment redis -n shopmicro --replicas=1
```

### Step 21: Kyverno Policies
```bash
make ev-19-policies
```
Wait 30s for Kyverno to install, then try to prove enforcement:
```bash
kubectl run test-bad --image=nginx -n shopmicro
```
This should be **BLOCKED** with: "CPU and memory limits are required."

**📸 SCREENSHOT [19/20]:** Terminal showing policies + blocked pod attempt.

### Step 22: Cost Analysis
```bash
make ev-20-cost
```
**📸 SCREENSHOT [20/20]:** Terminal showing cost breakdown.

---

## 🧹 CLEANUP

```bash
make tf-destroy
```
This runs `terraform init + destroy` automatically. Everything gets cleaned up.

**Wait for "Destroy complete!" — don't close terminal early.**

---

## 🆘 TROUBLESHOOTING

### "Module not installed" error on terraform
```bash
cd infrastructure/terraform && terraform init -reconfigure
```
Then retry the command.

### kubectl connection refused / TLS error
You probably didn't wait long enough for K3s to install. SSH in and check:
```bash
make ssh-master
sudo systemctl status k3s
sudo cat /var/log/k3s-install.log
```

### AlertManager CrashLoopBackOff
The Slack webhook URL is invalid. Fix `observability/manifests.yaml`, then:
```bash
kubectl apply -f observability/manifests.yaml
kubectl rollout restart deployment/alertmanager -n monitoring
```

### Pipeline fails on ECR push
Check that `GH_ACTIONS_ROLE_ARN` secret is set correctly in GitHub. The value should look like:
```
arn:aws:iam::307946680662:role/dev-github-actions-ecr-role
```

### Pipeline says "skipped" for build jobs
This means no files changed in `backend/`, `frontend/`, or `ml-service/`. Make a small change:
```bash
echo "// trigger build" >> backend/server.js
git add -A && git commit -m "trigger pipeline" && git push origin HEAD
```

### tf-destroy stuck or fails
```bash
cd infrastructure/terraform
terraform init -reconfigure
terraform destroy -auto-approve
```
If state is locked:
```bash
terraform force-unlock <LOCK_ID>
terraform destroy -auto-approve
```

---

## 📝 TOTAL SCREENSHOTS CHECKLIST

- [ ] 1. GitHub Actions pipeline passing (green ✓)
- [ ] 2. Terraform Apply complete
- [ ] 3. K3s nodes Ready
- [ ] 4. ArgoCD pods running
- [ ] 5. ArgoCD app synced (browser)
- [ ] 6. Pods status
- [ ] 7. Services + Ingress
- [ ] 8. HPA
- [ ] 9. Network policies
- [ ] 10. DevOps script output
- [ ] 11. Monitoring pods deployed
- [ ] 12. Prometheus UI (browser)
- [ ] 13. Grafana dashboard (browser)
- [ ] 14. AlertManager status (browser)
- [ ] 15. Slack alert notification
- [ ] 16. Rollback success
- [ ] 17. Canary deployment
- [ ] 18. Chaos experiments
- [ ] 19. Kyverno policy enforcement
- [ ] 20. Cost analysis
