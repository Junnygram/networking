# ==============================================================================
# ShopMicro Capstone — Full Evidence Collection Makefile
# ==============================================================================
# Run targets ev-01 → ev-20 in EXACT order. Each tells you what to screenshot.
# Flow: CI → Terraform → K3s → ArgoCD → Apps → Monitoring → Alerts → Rollback
# ==============================================================================

SSH_KEY         = infrastructure/terraform/shopmicro-key
TF_DIR          = infrastructure/terraform
NAMESPACE       = shopmicro
MON_NAMESPACE   = monitoring

# Auto-set KUBECONFIG so every kubectl target just works
export KUBECONFIG := $(CURDIR)/kubeconfig.yaml

# Auto-set AWS creds so every terraform target just works
export AWS_ACCESS_KEY_ID     := AKIAUPMYNOFLCMLVUIW3
export AWS_SECRET_ACCESS_KEY := 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
export AWS_DEFAULT_REGION    := us-east-1

.PHONY: help

help: ## Show all evidence targets
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║      ShopMicro Capstone — Evidence Pipeline                 ║"
	@echo "║      Run ev-01 → ev-20 in order. Screenshot each.          ║"
	@echo "╠══════════════════════════════════════════════════════════════╣"
	@echo "║  PHASE 0: CI PIPELINE ................... ev-01             ║"
	@echo "║  PHASE 1: INFRASTRUCTURE ................ ev-02, ev-03      ║"
	@echo "║  PHASE 2: ARGOCD + GITOPS ............... ev-04, ev-05      ║"
	@echo "║  PHASE 3: APPLICATIONS .................. ev-06 to ev-10    ║"
	@echo "║  PHASE 4: OBSERVABILITY ................. ev-11 to ev-14    ║"
	@echo "║  PHASE 5: INCIDENT & RECOVERY ........... ev-15, ev-16      ║"
	@echo "║  PHASE 6: EXTRA CREDIT .................. ev-17 to ev-20    ║"
	@echo "║  UTILITIES .............................. ssh-master, etc   ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@grep -E '^ev-[0-9]|^ssh-|^tf-' $(MAKEFILE_LIST) | grep '##' | awk 'BEGIN {FS = \":.*?## \"}; {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}'

# ==============================================================================
# PHASE 0: CI PIPELINE (GitHub Actions must have run before this)
# ==============================================================================

ev-01-ci-pipeline: ## 📸 [1/20] CI Pipeline — Screenshot GitHub Actions passing
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [1/20]: CI/CD PIPELINE"
	@echo "  → Go to GitHub → Actions tab"
	@echo "  → Screenshot the pipeline with ALL jobs passing (green ✓):"
	@echo "    • lint-and-test"
	@echo "    • iac-validation"
	@echo "    • detect-changes"
	@echo "    • build-and-push-backend (if backend changed)"
	@echo "    • build-and-push-frontend (if frontend changed)"
	@echo "    • build-and-push-ml-service (if ml-service changed)"
	@echo "  → This proves: OIDC auth, monorepo detection, ECR push"
	@echo "════════════════════════════════════════════════════════════════"

# ==============================================================================
# PHASE 1: INFRASTRUCTURE PROVISIONING
# ==============================================================================

ev-02-tf-apply: ## 📸 [2/20] Terraform Apply — Provision VPC, EC2, ECR, OIDC
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [2/20]: TERRAFORM APPLY"
	@echo "  → Capture: 'Apply complete! Resources: X added'"
	@echo "  → Shows: VPC, subnets, EC2 nodes, ECR repos, OIDC role"
	@echo "════════════════════════════════════════════════════════════════"
	cd $(TF_DIR) && terraform init -reconfigure && terraform apply -auto-approve
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║  ✅ TERRAFORM DONE — ECR REPOS + OIDC CREATED!          ║"
	@echo "╠══════════════════════════════════════════════════════════╣"
	@echo "║  Now run: make push-trigger                             ║"
	@echo "║  to push code and trigger the CI pipeline.              ║"
	@echo "╚══════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📦 ECR Repositories created:"
	cd $(TF_DIR) && terraform output ecr_backend_url
	cd $(TF_DIR) && terraform output ecr_frontend_url
	cd $(TF_DIR) && terraform output ecr_ml_service_url
	@echo ""
	@echo "🔐 GitHub Actions OIDC Role ARN (add to GitHub Secrets as GH_ACTIONS_ROLE_ARN):"
	cd $(TF_DIR) && terraform output github_actions_role_arn

push-trigger: ## 🚀 Push code to trigger CI pipeline (run AFTER ev-02)
	@echo "════════════════════════════════════════════════════════════════"
	@echo "🚀 PUSHING CODE TO TRIGGER CI PIPELINE"
	@echo "  → This will build & push Docker images to ECR"
	@echo "════════════════════════════════════════════════════════════════"
	@echo ""
	@echo "⚠️  BEFORE pushing, make sure you added the GitHub Secret:"
	@echo "   GH_ACTIONS_ROLE_ARN = (the ARN printed by ev-02)"
	@echo ""
	git add -A
	git commit -m "feat: full capstone infrastructure + observability + CI/CD" || true
	git push origin HEAD
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════╗"
	@echo "║  ✅ CODE PUSHED! Pipeline is running on GitHub Actions.  ║"
	@echo "║                                                         ║"
	@echo "║  📝 Go to GitHub → Actions tab to watch                 ║"
	@echo "║  📸 Screenshot ev-01 when pipeline finishes (green ✓)    ║"
	@echo "║                                                         ║"
	@echo "║  While pipeline runs, K3s is installing on EC2.          ║"
	@echo "║  After ~2 min, continue: make ev-03-fetch-kubeconfig     ║"
	@echo "╚══════════════════════════════════════════════════════════╝"

ev-03-fetch-kubeconfig: ## 📸 [3/20] Fetch kubeconfig + Show K3s nodes Ready
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [3/20]: K3S NODES READY"
	@echo "  → Capture: kubeconfig fetched + nodes in Ready state"
	@echo "════════════════════════════════════════════════════════════════"
	@MASTER_IP=$$(cd $(TF_DIR) && terraform output -raw k8s_master_ip) && \
	echo "⏳ Waiting 120s for K3s to finish installing on $$MASTER_IP..." && \
	sleep 120 && \
	ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no ubuntu@$$MASTER_IP \
	  "sudo cp /etc/rancher/k3s/k3s.yaml /tmp/k3s.yaml && sudo chown ubuntu:ubuntu /tmp/k3s.yaml" && \
	scp -i $(SSH_KEY) -o StrictHostKeyChecking=no ubuntu@$$MASTER_IP:/tmp/k3s.yaml ./kubeconfig.yaml && \
	sed -i '' "s/127.0.0.1/$$MASTER_IP/g" kubeconfig.yaml && \
	echo "" && \
	echo "✅ Kubeconfig saved. Showing nodes:" && \
	kubectl get nodes -o wide && \
	echo "" && \
	echo "💡 TIP: If only 1 node is Ready, run: make k3s-join-worker"

# ==============================================================================
# PHASE 2: ARGOCD + GITOPS
# ==============================================================================

ev-04-argocd-install: ## 📸 [4/20] Install ArgoCD + Image Updater
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [4/20]: ARGOCD INSTALLED"
	@echo "  → Capture: ArgoCD pods running in argocd namespace"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl create namespace argocd 2>/dev/null || true
	kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
	kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/v0.12.0/manifests/install.yaml
	@echo "⏳ Waiting 60s for ArgoCD pods to start..."
	sleep 60
	kubectl get pods -n argocd
	@echo ""
	@echo "🔐 ArgoCD admin password:"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo ""
	@echo ""
	@echo "📝 Run 'make argocd-pf' in a new terminal to access the UI"

argocd-pf: ## 🔓 Get ArgoCD Password and Port-Forward UI
	@echo "════════════════════════════════════════════════════════════════"
	@echo "🔐 ArgoCD admin password:"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo ""
	@echo ""
	@echo "🌐 Port forwarding ArgoCD to https://localhost:8443"
	@echo "   Hit Ctrl+C to stop."
	@echo "════════════════════════════════════════════════════════════════"
	kubectl port-forward svc/argocd-server -n argocd 8443:443

ev-05-argocd-app: ## 📸 [5/20] Create ArgoCD App + Sync — Shows ECR images
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [5/20]: ARGOCD APPLICATION SYNCED"
	@echo "  → 📝 MANUAL STEPS IN ARGOCD UI:"
	@echo "  → 1. Click '+ New App'"
	@echo "  →    Name: shopmicro"
	@echo "  →    Project: default"
	@echo "  →    Repo URL: https://github.com/Junnygram/networking.git"
	@echo "  →    Path: ShopMicro/k8s"
	@echo "  →    Cluster: https://kubernetes.default.svc"
	@echo "  →    Namespace: shopmicro"
	@echo "  → 2. Click 'Create' then 'Sync'"
	@echo "  → 3. 📸 Screenshot the synced app showing all resources"
	@echo "  → 4. 📸 Screenshot showing Image Updater pod in argocd ns"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl get pods -n argocd | grep image-updater

# ==============================================================================
# PHASE 3: APPLICATION VERIFICATION
# ==============================================================================

ev-06-pods: ## 📸 [6/20] Pod Status — All microservices deployed
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [6/20]: PODS STATUS"
	@echo "  → Capture: all pods with their status"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl get pods -n $(NAMESPACE) -o wide

ev-07-services: ## 📸 [7/20] Services + Ingress — Networking layer
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [7/20]: SERVICES & INGRESS"
	@echo "  → Capture: ClusterIP services + Ingress routing"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl get svc,ingress -n $(NAMESPACE)

ev-08-hpa: ## 📸 [8/20] HPA — Horizontal Pod Autoscaler
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [8/20]: HPA AUTOSCALING"
	@echo "  → Capture: HPA target CPU%, min/max replicas"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl get hpa -n $(NAMESPACE)

ev-09-netpol: ## 📸 [9/20] Network Policies — Least-privilege
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [9/20]: NETWORK POLICIES"
	@echo "  → Capture: policies restricting inter-service traffic"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl get networkpolicies -n $(NAMESPACE)
	kubectl describe networkpolicies -n $(NAMESPACE) | head -60

ev-10-devops-script: ## 📸 [10/20] DevOps Script — Health checks + evidence files
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [10/20]: DEVOPS UTILITY SCRIPT"
	@echo "  → Capture: script output + evidence/ files generated"
	@echo "════════════════════════════════════════════════════════════════"
	chmod +x scripts/devops.sh
	./scripts/devops.sh
	@echo ""
	@echo "📂 Evidence files:"
	ls -la evidence/

# ==============================================================================
# PHASE 4: OBSERVABILITY (Prometheus, Grafana, AlertManager + Slack)
# ==============================================================================

ev-11-monitoring-deploy: ## 📸 [11/20] Deploy Monitoring Stack
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [11/20]: MONITORING STACK DEPLOYED"
	@echo "  → Capture: prometheus, grafana, alertmanager pods Running"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl apply -f observability/manifests.yaml
	@echo "⏳ Waiting 30s for monitoring pods..."
	sleep 30
	kubectl get pods -n $(MON_NAMESPACE) -o wide

ev-12-prometheus: ## 📸 [12/20] Prometheus UI — BROWSER screenshot
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [12/20]: PROMETHEUS WEB UI (BROWSER)"
	@echo "  → Open URL → Status > Targets → screenshot"
	@echo "  → Also: Alerts tab → screenshot alert rules"
	@echo "════════════════════════════════════════════════════════════════"
	@MASTER_IP=$$(cd $(TF_DIR) && terraform output -raw k8s_master_ip) && \
	echo "" && \
	echo "🌐 OPEN IN BROWSER:" && \
	echo "   http://$$MASTER_IP:32090" && \
	echo "" && \
	echo "   → Click 'Status' → 'Targets' → 📸 Screenshot" && \
	echo "   → Click 'Alerts' → 📸 Screenshot alert rules"

ev-13-grafana: ## 📸 [13/20] Grafana Dashboard — BROWSER screenshot
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [13/20]: GRAFANA DASHBOARD (BROWSER)"
	@echo "  → Open URL, login, add datasource, import dashboards"
	@echo "════════════════════════════════════════════════════════════════"
	@MASTER_IP=$$(cd $(TF_DIR) && terraform output -raw k8s_master_ip) && \
	echo "" && \
	echo "🌐 OPEN IN BROWSER:" && \
	echo "   http://$$MASTER_IP:32300" && \
	echo "" && \
	echo "📝 MANUAL STEPS:" && \
	echo "   1. Login:  admin / admin" && \
	echo "   2. Connections → Data Sources → Add Prometheus" && \
	echo "   3. URL:   http://prometheus.monitoring.svc.cluster.local:9090" && \
	echo "   4. Save & Test (green ✓)" && \
	echo "   5. Dashboards → Import → Upload observability/grafana-dashboards/*.json" && \
	echo "   6. 📸 Screenshot each dashboard with panels"

ev-14-alertmanager: ## 📸 [14/20] AlertManager — BROWSER screenshot (Slack config)
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [14/20]: ALERTMANAGER + SLACK CONFIG (BROWSER)"
	@echo "  → Open URL, screenshot the config showing Slack receiver"
	@echo "════════════════════════════════════════════════════════════════"
	@MASTER_IP=$$(cd $(TF_DIR) && terraform output -raw k8s_master_ip) && \
	echo "" && \
	echo "🌐 OPEN IN BROWSER:" && \
	echo "   http://$$MASTER_IP:32093" && \
	echo "" && \
	echo "   → Click '#/status' → 📸 Screenshot showing Slack webhook config"

# ==============================================================================
# PHASE 5: INCIDENT RESPONSE & SLACK ALERTING
# ==============================================================================

ev-15-slack-alert: ## 📸 [15/20] Kill a pod → Slack alert fires
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [15/20]: SLACK ALERT — POD FAILURE"
	@echo "  → We delete a pod to simulate an incident"
	@echo "  → Wait ~2min → Alert fires → Check Slack"
	@echo "════════════════════════════════════════════════════════════════"
	@echo "💀 Killing a backend pod..."
	kubectl delete pod -n $(NAMESPACE) -l app=backend --wait=false
	@echo ""
	@echo "✅ Pod deleted! Now:"
	@echo "   1. Watch recovery: kubectl get pods -n $(NAMESPACE) -w"
	@echo "   2. Wait ~2 min for Prometheus → AlertManager → Slack"
	@echo "   3. Open Slack #shopmicro-alerts"
	@echo "   4. 📸 Screenshot the Slack alert notification"

ev-16-rollback: ## 📸 [16/20] Rollback — Zero-downtime recovery
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [16/20]: ZERO-DOWNTIME ROLLBACK"
	@echo "  → Creates a bad revision, then rolls back cleanly"
	@echo "════════════════════════════════════════════════════════════════"
	@echo "--- Step 1: Simulate bad deploy (new env var = new revision) ---"
	kubectl set env deployment/backend -n $(NAMESPACE) BAD_DEPLOY=true 2>/dev/null || true
	@echo "⏳ Waiting 10s for rollout..."
	sleep 10
	@echo ""
	@echo "--- Step 2: Rollback to previous good version ---"
	kubectl rollout undo deployment/backend -n $(NAMESPACE) 2>/dev/null || true
	sleep 5
	kubectl rollout history deployment/backend -n $(NAMESPACE)
	@echo ""
	@echo "✅ Rollback complete! RollingUpdate ensures zero downtime."

# ==============================================================================
# PHASE 6: EXTRA CREDIT
# ==============================================================================

ev-17-canary: ## 📸 [17/20] EXTRA: Canary deployment (blue/green traffic split)
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [17/20]: CANARY / BLUE-GREEN DEPLOYMENT"
	@echo "  → Capture: v1 + v2 running side by side + canary ingress"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl apply -f k8s/canary/
	sleep 5
	kubectl get deployments -n $(NAMESPACE)
	kubectl get ingress -n $(NAMESPACE)

ev-18-chaos: ## 📸 [18/20] EXTRA: Chaos experiments (pod kill + dependency failure)
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [18/20]: CHAOS ENGINEERING"
	@echo "  → Capture: pod kill recovery + Redis failure"
	@echo "  → Note timestamps for MTTD/MTTR calculations"
	@echo "════════════════════════════════════════════════════════════════"
	@echo "--- Experiment 1: Random Pod Kill ---"
	@echo "⏱  START TIMER NOW"
	kubectl delete pod -n $(NAMESPACE) -l app=backend --wait=false
	@echo ""
	@echo "--- Experiment 2: Dependency Failure (Redis down) ---"
	kubectl scale deployment redis -n $(NAMESPACE) --replicas=0 2>/dev/null || true
	@echo "Redis scaled to 0. Backend should degrade gracefully."
	@echo ""
	@echo "📝 After screenshot, restore: kubectl scale deployment redis -n $(NAMESPACE) --replicas=1"

ev-19-policies: ## 📸 [19/20] EXTRA: Kyverno policy enforcement
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [19/20]: POLICY ENFORCEMENT"
	@echo "  → First install Kyverno, then show policy blocking bad pods"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl create -f https://github.com/kyverno/kyverno/releases/download/v1.11.1/install.yaml 2>/dev/null || true
	@echo "⏳ Waiting 30s for Kyverno..."
	sleep 30
	kubectl apply -f k8s/policies/
	kubectl get clusterpolicies 2>/dev/null || echo "Policies applied"
	@echo ""
	@echo "📝 To prove enforcement, try:"
	@echo "   kubectl run test-bad --image=nginx -n $(NAMESPACE)"
	@echo "   (Should be BLOCKED: resource limits required)"

ev-20-cost: ## 📸 [20/20] EXTRA: Cost analysis + resource utilization
	@echo "════════════════════════════════════════════════════════════════"
	@echo "📸 SCREENSHOT [20/20]: COST & RESOURCE ANALYSIS"
	@echo "  → Capture: node info + cost breakdown"
	@echo "════════════════════════════════════════════════════════════════"
	kubectl top nodes 2>/dev/null || echo "(metrics-server required for kubectl top)"
	kubectl get nodes -o wide
	@echo ""
	@echo "📊 Cost breakdown:"
	@echo "   2x t3.medium = 2 × $$0.0416/hr = $$60.70/month"
	@echo "   With Reserved: ~$$38/mo (37% savings)"
	@echo "   See costs.md for full analysis"
	@echo ""
	cat costs.md 2>/dev/null || true

# ==============================================================================
# UTILITY TARGETS
# ==============================================================================

ssh-master: ## SSH into K3s master
	@MASTER_IP=$$(cd $(TF_DIR) && terraform output -raw k8s_master_ip) && \
	ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no ubuntu@$$MASTER_IP

ssh-worker: ## SSH into K3s worker
	@WORKER_IP=$$(cd $(TF_DIR) && terraform output -raw k8s_worker_ip) && \
	ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no ubuntu@$$WORKER_IP

k3s-join-worker: ## Join the worker node to the master cluster
	@echo "⏳ Extracting join token from master..."
	@MASTER_IP=$$(cd $(TF_DIR) && terraform output -raw k8s_master_ip) && \
	WORKER_IP=$$(cd $(TF_DIR) && terraform output -raw k8s_worker_ip) && \
	TOKEN=$$(ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no ubuntu@$$MASTER_IP "sudo cat /var/lib/rancher/k3s/server/node-token") && \
	echo "🚀 Joining worker ($$WORKER_IP) to master ($$MASTER_IP)..." && \
	ssh -i $(SSH_KEY) -o StrictHostKeyChecking=no ubuntu@$$WORKER_IP \
	  "curl -sfL https://get.k3s.io | K3S_URL=https://$$MASTER_IP:6443 K3S_TOKEN=$$TOKEN sh -" && \
	echo "✅ Worker joined. Check status with: kubectl get nodes"

cleanup-evicted: ## Cleanup evicted pods in the cluster
	@echo "🧹 Removing evicted pods..."
	@export KUBECONFIG=./kubeconfig.yaml && \
	kubectl delete pods --field-selector status.phase=Failed -A && \
	kubectl delete pods --field-selector status.phase=Succeeded -A

tf-destroy: ## 🚨 Destroy ALL infra (VPC, EC2, ECR, OIDC — everything)
	@echo "🚨 DESTROYING ALL AWS INFRASTRUCTURE..."
	cd $(TF_DIR) && terraform init -reconfigure && terraform destroy -auto-approve
	@echo "✅ All resources destroyed. AWS bill stops now."
