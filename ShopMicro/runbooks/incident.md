# Incident Runbook: Simulated High Latency in ML Service

## 1. Overview
This incident response runbook covers the scenario where the Machine Learning validation layer (e.g., `shopmicro-ml-service`) returns response times exceeding our p95 latency thresholds (>500ms).

*   **Incident Tier:** 2
*   **Primary Affected Service:** `ml-service` (Python/Flask)
*   **Trigger Mechanism:** Prometheus Alert (`HighLatency` from `alert-rules.yml`)
*   **SLO Impact:** API Latency 

---

## 2. Investigation Steps

### Step A: Verify the Scope of Latency
1. Log into Grafana and open the imported **Platform Overview** and **Backend Health** dashboards.
2. Review the time series to identify if the spike correlates with a traffic surge (HTTP request increments) or affects background processing delays explicitly.
3. Validate if the `ml-service` is crash looping.
   ```bash
   kubectl get pods -n shopmicro -l app=ml-service
   ```

### Step B: Inspect the Logs for Traces
Execute commands mapping to specific namespace application logging behavior indicating processing failures or downstream dependency hangs.
```bash
# Capture the last 200 lines 
kubectl logs -n shopmicro deploy/ml-service --tail=200
```

### Step C: Measure Cluster Topology Contention
Verify the Node executing the Pod hasn't exhausted resources. The `ml-service` relies on strict `tolerations` mapping to the `ml-workload`.
```bash
kubectl top pod -n shopmicro
kubectl describe node <Node hosting the ml-service>
```

---

## 3. Mitigation & Recovery

If the latency originates strictly due to pod saturation processing an unexpected surge:
1. **Immediate Scaling Fix:** Increase the pod capability explicitly forcing HPA re-evaluations or manual intervention.
```bash
kubectl scale deployment ml-service --replicas=3 -n shopmicro
```

If the latency stems from a newly deployed regression logic:
2. **Execute a Safe Downgrade:** Revert to the last known, safe, evaluated deployment container utilizing Kubernetes Rollout History commands.
```bash
kubectl rollout undo deployment/ml-service -n shopmicro
```

---

## 4. Post-Incident Review Requirements
* Review if the memory `limits: 256Mi` requires future-proofing modifications via Terraform topology definitions.
* Determine exactly which endpoint produced the delay (Captured from OTel tags in Grafana traces/Loki).
