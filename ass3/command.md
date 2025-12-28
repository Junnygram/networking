# Assignment 3: Manual Monitoring Commands

This document provides the step-by-step commands to manually use the monitoring tools, as an alternative to the `assignment3.sh` toolkit.

**Prerequisites:**
* The network and services from Assignments 1 & 2 must be running.
* You have installed the necessary system packages: `tcpdump`, `conntrack`, `python3-pip`.
* You have installed the `requests` Python library: `pip3 install requests`.

---

## 1. Traffic Monitor

This tool uses `tcpdump` to capture all network traffic flowing across the `br0` bridge.

### Command

Run the following command to start monitoring. Press `Ctrl+C` to stop.
```bash
sudo tcpdump -i br0 -n -v
```

---

## 2. Health Monitor

This tool is a Python script that periodically checks the `/health` endpoint of each service.

### Step 1: Create the `health-monitor.py` file
```bash
cat << 'EOF' > health-monitor.py
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
    try:
        response = requests.get(url, timeout=2)
        if response.status_code == 200:
            return {"status": "UP", "latency": response.elapsed.total_seconds()}
        else:
            return {"status": "DOWN", "error": f"HTTP {response.status_code}"}
    except requests.exceptions.RequestException as e:
        return {"status": "DOWN", "error": str(e)}

def monitor():
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
EOF
```

### Step 2: Run the script
```bash
python3 health-monitor.py
```
Press `Ctrl+C` to stop the monitor.

---

## 3. Connection Tracker

This tool uses `ss` and `conntrack` to provide a snapshot of active network connections.

### Command

This command will run a loop that clears the screen and shows updated connection info every 5 seconds. Press `Ctrl+C` to stop.
```bash
while true; do
    clear
    echo "=== Active Connections ($(date)) ==="
    echo ""
    echo "Connections by Service Namespace:"
    echo "--------------------------------"
    
    for ns in nginx-lb api-gateway product-service order-service; do
        if sudo ip netns list | grep -q "$ns"; then
            count=$(sudo ip netns exec $ns ss -tan | grep ESTAB | wc -l)
            echo "$ns: $count active connections"
        else
            echo "$ns: namespace not found"
        fi
    done
    
    echo ""
    echo "Connection States (conntrack):"
    echo "-------------------------------"
    sudo conntrack -L 2>/dev/null | grep "10.0.0" | \
        awk '{print $4}' | sort | uniq -c | sort -rn || echo "Conntrack table is empty or module not loaded."
    
    sleep 5
done
```

---

## 4. Topology Visualizer

This tool is a Python script that inspects the network namespaces and generates a text-based diagram of the topology.

### Step 1: Create the `topology-visualizer.py` file
```bash
cat << 'EOF' > topology-visualizer.py
#!/usr/bin/env python3
import subprocess
import re

def get_namespace_ips():
    try:
        ns_list_raw = subprocess.run(
            ['ip', 'netns', 'list'],
            capture_output=True, text=True, check=True
        ).stdout.strip().split('\n')
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
            match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)/.* scope global', result)
            if match:
                ips[ns] = match.group(1)
        except (subprocess.CalledProcessError, FileNotFoundError):
            ips[ns] = "Error reading IP"
    return ips

def draw_topology():
    ips = get_namespace_ips()
    print("=" * 70)
    print(" " * 25 + "NETWORK TOPOLOGY")
    print("=" * 70)
    print("\n                    Internet")
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
EOF
```

### Step 2: Run the script
```bash
sudo python3 topology-visualizer.py
```
This command requires `sudo` because it needs to inspect the network namespaces.
