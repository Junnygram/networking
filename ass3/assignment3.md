# Assignment 3: Monitoring and Debugging

This assignment focuses on creating a suite of monitoring and debugging tools to observe the health and traffic of the microservices environment you deployed in Assignment 2.

These scripts are designed to be run from the **host machine**, not from within a network namespace.

---

## ⚠️ Step 0: Prerequisites

Before you begin, ensure you have the necessary tools installed.

**1. System Packages:**
Install `tcpdump` for traffic analysis and `conntrack` for connection tracking.

```bash
# For Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y tcpdump conntrack
```

**2. Python Packages:**
The health monitor requires the `requests` library.

```bash
pip3 install requests
```

**3. Running Environment:**
This assignment assumes that:
*   The network from **Assignment 1** is running.
*   All the application services from **Assignment 2** are running.

---

## Task 3.1: Network Traffic Analysis

Create a script to monitor all traffic flowing across the `br0` bridge using `tcpdump`. This allows you to see all communication between your services in real-time.

**Create the `monitor-traffic.sh` script:**
```bash
#!/bin/bash
# monitor-traffic.sh

echo "=== Network Traffic Monitor ==="
echo "Monitoring bridge: br0"
echo "Press Ctrl+C to stop"
echo ""

# Monitor all traffic on the bridge, with verbose output.
# The '-i' flag specifies the interface.
# The '-n' flag prevents DNS resolution of IPs.
sudo tcpdump -i br0 -n -v
```
**To run it:** `sudo ./monitor-traffic.sh`

**Deliverable:** A report analyzing the traffic between services.

---

## Task 3.2: Service Health Monitoring

Create a Python script that periodically checks the `/health` endpoint of each service and reports its status and latency.

**Create the `health-monitor.py` script:**
```python
#!/usr/bin/env python3
import requests
import time
from datetime import datetime

SERVICES = {
    'nginx-lb': 'http://10.0.0.10:80/health',
    'api-gateway': 'http://10.0.0.20:3000/health',
    'product-service': 'http://10.0.0.30:5000/health',
    'order-service': 'http://10.0.0.40:5000/health',
}

def check_health(service_name, url):
    """Checks a single service endpoint."""
    try:
        # A timeout is crucial to prevent the monitor from hanging.
        response = requests.get(url, timeout=2)
        if response.status_code == 200:
            return {"status": "UP", "latency": response.elapsed.total_seconds()}
        else:
            return {"status": "DOWN", "error": f"HTTP {response.status_code}"}
    except requests.exceptions.RequestException as e:
        return {"status": "DOWN", "error": str(e)}

def monitor():
    """Main monitoring loop."""
    print("=== Service Health Monitor ===")
    print(f"Started at: {datetime.now()}")
    
    while True:
        print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Running Health Checks...")
        print("-" * 60)
        
        all_ok = True
        for service, url in SERVICES.items():
            health = check_health(service, url)
            status_symbol = "✅" if health['status'] == 'UP' else "❌"
            
            if health['status'] == 'UP':
                print(f"{status_symbol} {service:20s} UP   (latency: {health['latency']*1000:.2f}ms)")
            else:
                all_ok = False
                print(f"{status_symbol} {service:20s} DOWN | Reason: {health.get('error', 'Unknown')}")
        
        print("-" * 60)
        if all_ok:
            print("All services are operational.")

        time.sleep(10)

if __name__ == '__main__':
    try:
        monitor()
    except KeyboardInterrupt:
        print("\nMonitor stopped.")
```
**To run it:** `python3 ./health-monitor.py`

**Deliverable:** A running health monitoring dashboard.

---

## Task 3.3: Connection Tracking Analysis

Create a script to inspect the kernel's connection tracking table (`conntrack`). This is useful for debugging firewall rules and understanding active network flows.

**Create the `connection-tracker.sh` script:**
```bash
#!/bin/bash
# connection-tracker.sh

echo "=== Active Connection Tracker ==="
echo "Press Ctrl+C to stop"
echo ""

while true; do
    clear
    echo "=== Active Connections ($(date)) ==="
    echo ""
    
    echo "Connections by Service Namespace:"
    echo "--------------------------------"
    
    # Use 'ss' to count established TCP connections in each namespace
    for ns in nginx-lb api-gateway product-service order-service; do
        # Ensure the namespace exists before trying to exec into it
        if sudo ip netns list | grep -q "$ns"; then
            count=$(sudo ip netns exec $ns ss -tan | grep ESTAB | wc -l)
            echo "$ns: $count active connections"
        else
            echo "$ns: namespace not found"
        fi
    done
    
    echo ""
    echo "Connection States (conntrack):"
    echo "------------------------------"
    # Use conntrack to view states for our specific subnet
    sudo conntrack -L 2>/dev/null | grep "10.0.0" | \
        awk '{print $4}' | sort | uniq -c | sort -rn
    
    sleep 5
done
```
**To run it:** `sudo ./connection-tracker.sh`

**Deliverable:** A connection tracking report.

---

## Task 3.4: Network Topology Visualizer

Create a Python script that inspects the network configuration and generates a simple text-based diagram of the topology.

**Create the `topology-visualizer.py` script:**
```python
#!/usr/bin/env python3
# topology-visualizer.py

import subprocess
import re

def get_namespace_ips():
    """Get IP addresses for all namespaces."""
    try:
        ns_list_raw = subprocess.run(
            ['ip', 'netns', 'list'],
            capture_output=True, text=True, check=True
        ).stdout.strip().split('\n')
        # Extract the first word from each line, which is the namespace name
        namespaces = [line.split()[0] for line in ns_list_raw]
    except (subprocess.CalledProcessError, FileNotFoundError):
        return {}
    
    ips = {}
    for ns in namespaces:
        try:
            result = subprocess.run(
                ['sudo', 'ip', 'netns', 'exec', ns, 'ip', 'addr'],
                capture_output=True, text=True, check=True
            ).stdout
            # Parse IP address from the 'inet' line
            match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', result)
            if match:
                ips[ns] = match.group(1)
        except (subprocess.CalledProcessError, FileNotFoundError):
            ips[ns] = "Error reading IP"
    
    return ips

def draw_topology():
    """Draw ASCII network topology."""
    ips = get_namespace_ips()
    
    print("=" * 70)
    print(" " * 25 + "NETWORK TOPOLOGY")
    print("=" * 70)
    print()
    print("                    Internet")
    print("                        │")
    print("                        │ (Host NAT)")
    print("                        ↓")
    print("                ┌───────────────┐")
    print("                │   Host Machine  │")
    print("                └───────┬───────┘")
    print("                        │")
    print("            ┌───────────┴───────────┐")
    print("            │     Bridge: br0         │")
    print("            │     IP: 10.0.0.1        │")
    print("            └───────────┬───────────┘")
    print("                        │")
    
    if not ips:
        print("\nNo network namespaces found or 'ip' command is missing.")
    else:
        for name, ip in sorted(ips.items()):
            print(f"                ├─▶ {name:20s} ({ip})")
    
    print("\n" + "=" * 70)

if __name__ == '__main__':
    draw_topology()
```
**To run it:** `sudo python3 ./topology-visualizer.py` (requires sudo to inspect namespaces).

**Deliverable:** A generated network topology diagram.
