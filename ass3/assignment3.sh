#!/bin/bash

# ===================================================================================
# Assignment 3 - Monitoring Toolkit Script
#
# This script bundles the monitoring tools for Assignment 3 into a single,
# easy-to-use toolkit. It also handles the installation of its own prerequisites.
#
# It assumes:
#   1. The network from `assignment1.sh` is running.
#   2. The services from `assignment2.sh` are running.
#
# Usage:
#   sudo ./assignment3.sh <tool>
#
# Available tools:
#   traffic       - Monitor raw network traffic on the bridge using tcpdump.
#   health        - Periodically check the /health endpoint of each service.
#   connections   - Track active network connections using ss and conntrack.
#   topology      - Display a text-based diagram of the network topology.
#
# ===================================================================================

# Exit on any error
set -e

# --- Tool-specific prerequisites ---
declare -A PREREQS
PREREQS["traffic"]="tcpdump"
PREREQS["health"]="python3 python3-pip"
PREREQS["connections"]="iproute2 conntrack" # iproute2 provides 'ss'
PREREQS["topology"]="python3"

# --- Function to install missing prerequisites ---
install_prereqs() {
    local tool=$1
    local missing_pkgs=()

    # Check for required packages for the selected tool
    for pkg in ${PREREQS[$tool]}; do
        # Use dpkg-query to check if a package is installed on Debian-based systems
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            missing_pkgs+=("$pkg")
        fi
    done

    if [ ${#missing_pkgs[@]} -gt 0 ]; then
        echo "--- Installing missing prerequisites for '$tool': ${missing_pkgs[*]} ---"
        if command -v apt-get >/dev/null; then
            sudo apt-get update
            sudo apt-get install -y "${missing_pkgs[@]}"
        else
            echo "ERROR: apt-get not found. Please install '${missing_pkgs[*]}' manually." >&2
            exit 1
        fi
    fi

    # Specific check for python 'requests' library for the health tool
    if [ "$tool" == "health" ]; then
        if ! python3 -c "import requests" 2>/dev/null; then
            echo "--- Installing 'requests' Python package ---"
            python3 -m pip install --user requests
        fi
    fi
}

# === TOOL IMPLEMENTATIONS ===

# --- 1. Traffic Monitor ---
run_traffic_monitor() {
    echo "=== Network Traffic Monitor ==="
    echo "Monitoring bridge: br0 (Press Ctrl+C to stop)"
    echo ""
    sudo tcpdump -i br0 -n -v
}

# --- 2. Health Monitor ---
run_health_monitor() {
    echo "--- Creating and running health monitor ---"
    # Create a temporary python script to run
    local SCRIPT_PATH="/tmp/health-monitor.py"
    
    cat <<'EOF' > "$SCRIPT_PATH"
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

    # Run the created script
    python3 "$SCRIPT_PATH"
    # Clean up the script afterwards
    rm -f "$SCRIPT_PATH"
}

# --- 3. Connection Tracker ---
run_connection_tracker() {
    echo "=== Active Connection Tracker ==="
    echo "Press Ctrl+C to stop"
    
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
}

# --- 4. Topology Visualizer ---
run_topology_visualizer() {
    echo "--- Creating and running topology visualizer ---"
    local SCRIPT_PATH="/tmp/topology-visualizer.py"

    cat <<'EOF' > "$SCRIPT_PATH"
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
            match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', result)
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
    
    # This script needs sudo to inspect namespaces
    sudo python3 "$SCRIPT_PATH"
    rm -f "$SCRIPT_PATH"
}


# --- Main script logic ---
TOOL=$1

if [ -z "$TOOL" ]; then
    echo "Usage: sudo $0 {traffic|health|connections|topology}"
    exit 1
fi

# Check if the chosen tool is valid
if [[ ! " ${!PREREQS[@]} " =~ " ${TOOL} " ]]; then
    echo "Error: Invalid tool '$TOOL'."
    echo "Available tools: ${!PREREQS[@]}"
    exit 1
fi

# Install prerequisites for the chosen tool
install_prereqs "$TOOL"

# Run the selected tool
case "$TOOL" in
    traffic)
        run_traffic_monitor
        ;;
    health)
        run_health_monitor
        ;;
    connections)
        run_connection_tracker
        ;;
    topology)
        run_topology_visualizer
        ;;
esac

exit 0
