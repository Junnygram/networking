#!/bin/bash

# ===================================================================================
# Assignment 4 - Advanced Networking Toolkit
#
# This script manages the advanced networking components for Assignment 4.
# It can start/stop a service registry and apply/remove iptables security policies.
#
# It assumes:
#   1. The network from `assignment1.sh` is running.
#   2. The services from `assignment2.sh` are running.
#
# Usage:
#   sudo ./assignment4.sh <command>
#
# Available commands:
#   start-registry    - Creates and runs the service registry Python app.
#   stop-registry     - Stops the service registry.
#
#   apply-policies    - Applies a restrictive set of iptables firewall rules.
#   remove-policies   - Flushes all firewall rules and resets the default policy.
#   show-policies     - Lists the current FORWARD chain iptables rules.
#
# ===================================================================================

# Exit on any error
set -e

# --- Prerequisites Check ---
install_prereqs() {
    local tool=$1
    local pkgs_to_install=()

    if [[ "$tool" == "registry" ]]; then
        if ! python3 -c "import flask" 2>/dev/null; then
            echo "--- Python 'Flask' package not found. Attempting to install... ---"
            python3 -m pip install --user Flask
        fi
    fi

    if [[ "$tool" == "policies" ]]; then
        if ! command -v iptables > /dev/null; then
            pkgs_to_install+=("iptables")
        fi
    fi
    
    if [ ${#pkgs_to_install[@]} -gt 0 ]; then
        echo "--- Installing missing prerequisites: ${pkgs_to_install[*]} ---"
        if command -v apt-get >/dev/null; then
            sudo apt-get update
            sudo apt-get install -y "${pkgs_to_install[@]}"
        else
            echo "ERROR: apt-get not found. Please install '${pkgs_to_install[*]}' manually." >&2
            exit 1
        fi
    fi
}


# === SERVICE REGISTRY FUNCTIONS ===

# --- 1. Start Service Registry ---
start_registry() {
    install_prereqs "registry"

    local SCRIPT_PATH="./service-registry.py"
    echo "--- Creating and running service registry at $SCRIPT_PATH ---"

    cat <<'EOF' > "$SCRIPT_PATH"
#!/usr/bin/env python3
from flask import Flask, jsonify, request
import time

app = Flask(__name__)
services = {}

@app.route('/register', methods=['POST'])
def register_service():
    data = request.json
    if not data or 'name' not in data or 'ip' not in data or 'port' not in data:
        return jsonify({"error": "Invalid registration data"}), 400
    service_name = data['name']
    services[service_name] = {
        'ip': data['ip'],
        'port': data['port'],
        'registered_at': time.time(),
    }
    print(f"Registered service: {service_name} at {data['ip']}:{data['port']}")
    return jsonify({"status": "registered", "service": service_name})

@app.route('/discover/<service_name>', methods=['GET'])
def discover_service(service_name):
    if service_name in services:
        return jsonify(services[service_name])
    else:
        return jsonify({"error": "Service not found"}), 404

@app.route('/services', methods=['GET'])
def list_services():
    return jsonify(services)

@app.route('/deregister/<service_name>', methods=['DELETE'])
def deregister_service(service_name):
    if service_name in services:
        del services[service_name]
        print(f"Deregistered service: {service_name}")
        return jsonify({"status": "deregistered"})
    else:
        return jsonify({"error": "Service not found"}), 404

if __name__ == '__main__':
    print("Service Registry running on http://0.0.0.0:8500")
    app.run(host='0.0.0.0', port=8500)
EOF

    # Run the registry in the background
    python3 "$SCRIPT_PATH" &
    echo "✅ Service Registry started in the background."
    echo "   To test, run: curl http://127.0.0.1:8500/services"
}

# --- 2. Stop Service Registry ---
stop_registry() {
    echo "--- Stopping service registry ---"
    pkill -f "python3 ./service-registry.py" || echo "Registry was not running."
    rm -f ./service-registry.py
    echo "✅ Service Registry stopped and file deleted."
}


# === SECURITY POLICY FUNCTIONS ===

# --- 3. Apply Security Policies ---
apply_policies() {
    install_prereqs "policies"
    echo "--- Applying iptables security policies ---"

    # Set the default policy for the FORWARD chain to DROP.
    # This means any traffic not explicitly allowed will be denied.
    echo "Setting default FORWARD policy to DROP"
    sudo iptables -P FORWARD DROP

    # Allow traffic from Nginx LB to API Gateway
    echo "Allowing Nginx -> API Gateway"
    sudo iptables -A FORWARD -s 10.0.0.10 -d 10.0.0.20 -p tcp --dport 3000 -j ACCEPT

    # Allow traffic from API Gateway to Product and Order services
    echo "Allowing API Gateway -> Backend Services"
    sudo iptables -A FORWARD -s 10.0.0.20 -d 10.0.0.30 -p tcp --dport 5000 -j ACCEPT
    sudo iptables -A FORWARD -s 10.0.0.20 -d 10.0.0.40 -p tcp --dport 5000 -j ACCEPT

    # Allow traffic from Product Service to Redis
    echo "Allowing Product Service -> Redis"
    sudo iptables -A FORWARD -s 10.0.0.30 -d 10.0.0.50 -p tcp --dport 6379 -j ACCEPT

    # Allow traffic from Order Service to PostgreSQL
    echo "Allowing Order Service -> PostgreSQL"
    sudo iptables -A FORWARD -s 10.0.0.40 -d 10.0.0.60 -p tcp --dport 5432 -j ACCEPT

    # CRITICAL: Allow return traffic for all established connections
    echo "Allowing established and related traffic"
    sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow all services to make outbound requests for DNS and Web
    echo "Allowing outbound DNS and web traffic"
    sudo iptables -A FORWARD -s 10.0.0.0/24 -p udp --dport 53 -j ACCEPT
    sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 53 -j ACCEPT
    sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 80 -j ACCEPT
    sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 443 -j ACCEPT

    # Log dropped packets to kernel log for debugging
    echo "Adding rule to log dropped packets"
    sudo iptables -A FORWARD -j LOG --log-prefix "FW_DROPPED: " --log-level 4

    echo ""
    echo "✅ Security policies applied. Default policy is now DROP."
}

# --- 4. Remove Security Policies ---
remove_policies() {
    install_prereqs "policies"
    echo "--- Removing all iptables security policies ---"
    
    # Set the default policy back to ACCEPT
    sudo iptables -P FORWARD ACCEPT
    
    # Flush all rules from the FORWARD chain
    sudo iptables -F FORWARD
    
    echo "✅ All FORWARD chain rules have been flushed. Default policy is now ACCEPT."
}

# --- 5. Show Security Policies ---
show_policies() {
    install_prereqs "policies"
    echo "--- Current iptables FORWARD chain rules ---"
    sudo iptables -L FORWARD -v -n --line-numbers
}


# --- Main script logic ---
case "$1" in
    start-registry)
        start_registry
        ;;
    stop-registry)
        stop_registry
        ;;
    apply-policies)
        apply_policies
        ;;
    remove-policies)
        remove_policies
        ;;
    show-policies)
        show_policies
        ;;
    *)
        echo "Usage: sudo $0 {start-registry|stop-registry|apply-policies|remove-policies|show-policies}"
        exit 1
        ;;
esac

exit 0
