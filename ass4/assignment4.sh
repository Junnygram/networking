#!/bin/bash

# ===================================================================================
# Assignment 4 - Advanced Networking Toolkit (v2 - Integrated venv)
#
# This script manages the advanced networking components for Assignment 4.
# It uses the shared Python virtual environment created in Assignment 2 for
# consistency and proper package management.
#
# It can start/stop a service registry and apply/remove iptables security policies.
#
# It assumes:
#   1. The network from `assignment1.sh` is running.
#   2. The services from `assignment2.sh` are running.
#   3. The `networking_venv` from Assignment 2 exists or can be created.
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

# --- Global variables for venv and command paths ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VENV_DIR="$SCRIPT_DIR/../networking_venv" # Assumes venv is in parent directory
PYTHON_CMD="" # Will be set to $VENV_DIR/bin/python
PIPX_CMD=""   # Will be set to $VENV_DIR/bin/pip

# --- Prerequisites Check and Installation ---
install_prereqs_system_packages() {
    local pkgs_to_install=()
    local required_system_packages=("iptables" "python3-venv" "python3-pip") # Add python-venv/pip for venv setup

    if ! command -v apt-get >/dev/null; then
        echo "WARNING: apt-get not found. Cannot automatically install system packages." >&2
        echo "Please install the following packages manually: ${required_system_packages[*]}" >&2
        return 1
    fi

    for pkg in "${required_system_packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            pkgs_to_install+=("$pkg")
        fi
    done

    if [ ${#pkgs_to_install[@]} -gt 0 ]; then
        echo "Updating apt package list..."
        sudo apt-get update
        echo "Installing system packages: ${pkgs_to_install[*]}..."
        sudo apt-get install -y "${pkgs_to_install[@]}"
    fi
    return 0
}

ensure_python_venv() {
    echo "--- Ensuring Python virtual environment is set up ---"
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating Python virtual environment at $VENV_DIR..."
        python3 -m venv "$VENV_DIR"
        # Ensure pip is up-to-date in the new venv
        "$PYTHON_CMD" -m pip install -U pip
    fi

    # Ensure Flask is installed in the venv
    if ! "$PYTHON_CMD" -c "import flask" 2>/dev/null; then
        echo "--- Installing 'Flask' Python package into venv ---"
        "$PYTHON_CMD" -m pip install Flask
    fi
    echo "✅ Python virtual environment ready."
    return 0
}

discover_commands() {
    echo "--- Discovering required command paths ---"
    local missing_any=0

    # Ensure system prerequisites like iptables and venv tools are installed
    install_prereqs_system_packages

    # Set Python command to the virtual environment's python
    PYTHON_CMD="$VENV_DIR/bin/python"
    PIPX_CMD="$VENV_DIR/bin/pip" # Not strictly needed as we use python -m pip

    if [ ! -x "$PYTHON_CMD" ]; then
        echo "  - Python (in venv): MISSING"
        missing_any=1
    fi
    if ! command -v iptables > /dev/null; then # Re-check iptables after install attempt
        echo "  - iptables: MISSING"
        missing_any=1
    fi

    if [ "$missing_any" -eq 1 ]; then
        echo "Some commands/venv are missing. Attempting to ensure venv setup..."
        if ensure_python_venv; then
            # Re-discover Python command after venv setup
            PYTHON_CMD="$VENV_DIR/bin/python"
            if [ ! -x "$PYTHON_CMD" ] || ! command -v iptables > /dev/null; then
                echo "ERROR: Some commands are still missing after installation attempt. Please check manually." >&2
                exit 1
            fi
        else
            echo "ERROR: Python virtual environment setup failed. Please check manually." >&2
            exit 1
        fi
    fi

    echo "✅ All required commands found."
}


# === SERVICE REGISTRY FUNCTIONS ===

# --- 1. Start Service Registry ---
start_registry() {
    discover_commands # Ensure venv and python are ready

    local SCRIPT_PATH="$SCRIPT_DIR/service-registry.py"
    echo "--- Creating and running service registry at $SCRIPT_PATH ---"

    # Create the Python script
    cat <<'EOF' > "$SCRIPT_PATH"
#!/usr/bin/env python3
from flask import Flask, jsonify, request
import time, os, sys

app = Flask(__name__)
services = {} # In-memory registry

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
    print(f"Registered service: {service_name} at {data['ip']}:{data['port']}", file=sys.stderr)
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
        print(f"Deregistered service: {service_name}", file=sys.stderr)
        return jsonify({"status": "deregistered"})
    else:
        return jsonify({"error": "Service not found"}), 404

if __name__ == '__main__':
    print("Service Registry running on http://0.0.0.0:8500", file=sys.stderr)
    try:
        app.run(host='0.0.0.0', port=8500, debug=False) # Ensure debug is False
    except Exception as e:
        print(f"CRITICAL: Failed to start Flask app: {e}", file=sys.stderr)
        sys.exit(1)
EOF
    chmod +x "$SCRIPT_PATH"

    # Ensure no old registry is running
    sudo pkill -9 -f "$SCRIPT_PATH" || true
    sleep 0.5

    # Run the registry in the background using the venv python
    "$PYTHON_CMD" "$SCRIPT_PATH" > /tmp/service-registry.log 2>&1 &
    echo "✅ Service Registry started in the background."
    echo "   Log available at: /tmp/service-registry.log"
    echo "   To test, run: curl http://127.0.0.1:8500/services"
}

# --- 2. Stop Service Registry ---
stop_registry() {
    echo "--- Stopping service registry ---"
    sudo pkill -9 -f "$SCRIPT_DIR/service-registry.py" || echo "Registry was not running."
    rm -f "$SCRIPT_DIR/service-registry.py" # Delete generated script
    rm -f /tmp/service-registry.log # Clean up log file
    echo "✅ Service Registry stopped and file deleted."
}


# === SECURITY POLICY FUNCTIONS ===

# --- 3. Apply Security Policies ---
apply_policies() {
    discover_commands # Ensure iptables is available
    echo "--- Applying iptables security policies ---"

    # Ensure iptables default policy is ACCEPT before flushing, to avoid locking out.
    sudo iptables -P FORWARD ACCEPT
    sudo iptables -F FORWARD # Flush existing FORWARD rules

    echo "Setting default FORWARD policy to DROP"
    sudo iptables -P FORWARD DROP

    echo "Allowing Nginx (10.0.0.10) -> API Gateway (10.0.0.20)"
    sudo iptables -A FORWARD -s 10.0.0.10 -d 10.0.0.20 -p tcp --dport 3000 -j ACCEPT

    echo "Allowing API Gateway (10.0.0.20) -> Product Service (10.0.0.30)"
    sudo iptables -A FORWARD -s 10.0.0.20 -d 10.0.0.30 -p tcp --dport 5000 -j ACCEPT
    
    echo "Allowing API Gateway (10.0.0.20) -> Order Service (10.0.0.40)"
    sudo iptables -A FORWARD -s 10.0.0.20 -d 10.0.0.40 -p tcp --dport 5000 -j ACCEPT

    echo "Allowing Product Service (10.0.0.30) -> Redis (10.0.0.50)"
    sudo iptables -A FORWARD -s 10.0.0.30 -d 10.0.0.50 -p tcp --dport 6379 -j ACCEPT

    echo "Allowing Order Service (10.0.0.40) -> PostgreSQL (10.0.0.1)" # Host DB
    sudo iptables -A FORWARD -s 10.0.0.40 -d 10.0.0.1 -p tcp --dport 5432 -j ACCEPT

    echo "Allowing established and related traffic"
    sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    echo "Allowing outbound DNS and web traffic from 10.0.0.0/24"
    sudo iptables -A FORWARD -s 10.0.0.0/24 -p udp --dport 53 -j ACCEPT
    sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 53 -j ACCEPT
    sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 80 -j ACCEPT
    sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 443 -j ACCEPT

    echo "Adding rule to log dropped packets"
    sudo iptables -A FORWARD -j LOG --log-prefix "FW_DROPPED: " --log-level 4

    echo "✅ Security policies applied. Default policy for FORWARD is now DROP."
    echo "   Verify with: sudo iptables -L FORWARD -v -n --line-numbers"
}

# --- 4. Remove Security Policies ---
remove_policies() {
    discover_commands # Ensure iptables is available
    echo "--- Removing all iptables security policies ---"
    
    sudo iptables -P FORWARD ACCEPT # Set default policy to ACCEPT before flushing
    sudo iptables -F FORWARD # Flush all rules from the FORWARD chain
    
    echo "✅ All FORWARD chain rules have been flushed. Default policy is now ACCEPT."
}

# --- 5. Show Security Policies ---
show_policies() {
    discover_commands # Ensure iptables is available
    echo "--- Current iptables FORWARD chain rules ---"
    sudo iptables -L FORWARD -v -n --line-numbers || echo "No FORWARD rules set."
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