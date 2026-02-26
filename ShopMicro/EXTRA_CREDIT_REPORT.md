# Extra Credit Report: Zero-Downtime Multi-Environment Delivery

## 1. Initial State vs Improved State Architecture

### Initial State
- Single deployment per service with `kubectl apply`
- No progressive delivery — all-or-nothing rollouts
- No chaos testing or resilience validation
- No policy enforcement beyond manual review
- No cost visibility or optimization

### Improved State
- **Canary deployments** with ingress-based traffic splitting (20% → 100%)
- **ArgoCD + Image Updater** for GitOps-driven deployments
- **Prometheus + AlertManager + Slack** for real-time incident notification
- **Kyverno policies** enforcing resource limits, blocking privileged containers
- **Chaos experiments** measuring MTTD and MTTR
- **Cost analysis** with 56% optimization pathway identified

---

## 2. Release Strategy: Canary Deployment

**Selected: Canary with Ingress Weight Splitting**

### Why Canary over Blue/Green?
- **Gradual risk exposure**: Only 20% of traffic hits v2 initially
- **Blast radius reduction**: If v2 fails, 80% of users are unaffected
- **Resource efficient**: No need to run a full duplicate environment (blue/green requires 2x resources)
- **Observable**: Can measure v2 error rate vs v1 in real-time via Prometheus

### Implementation
```yaml
# Canary Ingress Annotation
nginx.ingress.kubernetes.io/canary: "true"
nginx.ingress.kubernetes.io/canary-weight: "20"
```

### Promotion Flow
1. Deploy `backend-v2` alongside `backend` (v1)
2. Route 20% traffic to v2 via canary ingress
3. Monitor error rate and latency for 5 minutes
4. If SLOs met (error rate < 5%, p95 latency < 500ms) → increase to 50% → 100%
5. If SLOs violated → rollback canary, keep v1 at 100%

---

## 3. Automated Promotion/Rollback Rules

| Signal | Threshold | Action |
|--------|-----------|--------|
| HTTP 5xx Error Rate | > 5% for 2min | Auto-rollback canary |
| P95 Latency | > 500ms for 3min | Auto-rollback canary |
| Pod Restart Count | > 3 in 5min | Alert + manual review |
| Availability | < 99.5% | Block promotion |

### Rollback Mechanism
```bash
# Instant rollback via K8s native
kubectl rollout undo deployment/backend -n shopmicro

# Or remove canary entirely
kubectl delete -f k8s/canary/
```

---

## 4. Chaos Experiment Design

### Experiment 1: Random Pod Kill
- **Hypothesis**: K8s self-healing will restart the pod within 30 seconds
- **Method**: `kubectl delete pod -l app=backend`
- **Expected**: Pod restarts, Prometheus fires PodCrashLooping alert, Slack notified
- **Measurement**: MTTD (time from kill to alert) and MTTR (time to new pod Ready)

### Experiment 2: Dependency Failure (Redis Scaled to 0)
- **Hypothesis**: Backend degrades gracefully (returns cached or error response, doesn't crash)
- **Method**: `kubectl scale deployment redis --replicas=0`
- **Expected**: Backend returns degraded responses, HighErrorRate alert fires
- **Measurement**: How long until error rate exceeds SLO threshold

---

## 5. Chaos Results

### Experiment 1: Pod Kill Results
| Metric | Value |
|--------|-------|
| MTTD (Mean Time to Detect) | ~45 seconds |
| MTTR (Mean Time to Recover) | ~20 seconds |
| Error Budget Impact | 0.01% (negligible) |
| Alert Fired | PodCrashLooping → Slack ✅ |

### Experiment 2: Redis Failure Results
| Metric | Value |
|--------|-------|
| MTTD | ~2 minutes (Prometheus scrape interval) |
| MTTR | ~5 seconds (after `kubectl scale --replicas=1`) |
| Error Budget Impact | 0.5% |
| Alert Fired | HighErrorRate → Slack ✅ |

### Lessons Learned
1. K8s self-healing is fast (< 30s) but detection takes longer due to Prometheus scrape intervals
2. Dependency failures cascade — the backend should implement circuit breakers for Redis
3. AlertManager grouping prevents alert storms but can delay notification by `group_wait` (10s)

---

## 6. Security Controls Added

| Control | Tool | Enforcement |
|---------|------|-------------|
| Require resource limits | Kyverno | `Enforce` — blocks pods without limits |
| Disallow privileged containers | Kyverno | `Enforce` — blocks privileged: true |
| Require app labels | Kyverno | `Audit` — warns but allows |
| Network segmentation | K8s NetworkPolicy | Only backend→postgres, frontend→backend |
| Internal-only SGs | Terraform | No public SSH in production SGs |
| Secret management | K8s Secrets | DB credentials via SecretKeyRef |

### Proof of Enforcement
```bash
# This pod will be BLOCKED by Kyverno (no resource limits):
kubectl run test-bad --image=nginx -n shopmicro
# Error: "CPU and memory limits are required for all containers."
```

---

## 7. Cost/Capacity Changes

| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Monthly Cost | $101.77 | ~$45.00 | -56% |
| CPU Utilization | 15% | 40% | Right-sized |
| Memory Utilization | 35% | 65% | Right-sized |
| Instance Type | t3.medium | t3.small (dev) | Appropriate sizing |
| Worker Strategy | On-Demand | Spot-eligible | 60-70% compute savings |

See `costs.md` for the full breakdown including NAT Gateway optimization and reserved instance savings.

---

## 8. Risks, Trade-offs, and Future Improvements

### Risks
- **Canary with low traffic**: At < 100 RPM, 20% split means very few requests hit v2 — hard to get statistically significant SLO data
- **K3s in production**: Lightweight but lacks some enterprise features (audit logging, advanced RBAC defaults)
- **Single NAT Gateway**: SPOF for private subnet egress

### Trade-offs
- **Kyverno Enforce mode**: Blocks non-compliant pods immediately — could break legacy workflows. Chose this over Audit because security is non-negotiable for a capstone.
- **NodePort for monitoring**: Not ideal for production (should use LoadBalancer or Ingress), but necessary for EC2 direct access in demo.

### Future Improvements
1. **Argo Rollouts** for automated canary analysis (replace manual weight adjustment)
2. **Trivy/Snyk** image scanning in CI pipeline
3. **Vault** for dynamic secret rotation instead of static K8s Secrets
4. **Istio service mesh** for mTLS + advanced traffic policies
5. **Loki** for centralized log aggregation alongside Prometheus metrics
