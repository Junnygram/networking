# Test Report: E-Commerce Platform

## 1. Service Discovery Test
**Objective:** Verify pods can resolve each other by service name.
-   **Method:** Executed `nslookup postgres` and `nslookup redis` from inside the backend pod.
-   **Result:** **Success**. DNS correctly resolved service names to their ClusterIPs.

## 2. Load Balancing Test
**Objective:** Verify traffic is distributed across replicas.
-   **Method:** Accessed Frontend Service via NodePort multiple times.
-   **Result:** **Success**. Traffic reaches the Service, which distributes it to the 6 running frontend pods via kube-proxy.

## 3. Self-Healing Test
**Objective:** Verify resiliency during node failure.
-   **Method:** Executed `kubectl drain worker-node-1`.
-   **Observation:**
    -   Frontend pods (pinned to Node 1) became Pending (Correct, no other node matched selector).
    -   Redis pod (on Node 1) was evicted and successfully rescheduled to Node 2 (Correct, satisfied anti-affinity).
-   **Result:** **Partial Success** (System behaved exactly as configured, highlighting the trade-off of strict Node Selectors).

## 4. Scaling & Performance
**Objective:** Verify cluster scaling capabilities.
-   **Test:** Scaled `frontend` to 6 replicas and `batch-processor` to 10 replicas.
-   **Result:** **Success**. All pods scheduled successfully. T3.medium nodes handled the CPU/Memory requests (100m/200m respectively) without exhaustion in this test scenario.

## 5. Deployment Troubleshooting
**Objective:** recovering from a broken state.
-   **Scenario:** Deployed 'broken-app' with invalid 5000m CPU request.
-   **Result:** Pods stuck in Pending.
-   **Fix:** Updated requests to 50m. Pods started immediately.
