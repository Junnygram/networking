#!/bin/bash

# ===================================================================================
# Assignment 6 - Multi-Host Networking Helper Script (v2 - with Auto-Install)
#
# This script provides helper functions for setting up multi-host networking
# and now attempts to automatically install Docker if it is missing.
#
# IMPORTANT: This script is a HELPER. You must run appropriate commands
#            on each target host.
#
# ===================================================================================

set -e

# --- Prerequisite Installation ---
install_prerequisites() {
    echo "--- Attempting to install missing prerequisites... ---"
    
    if ! command -v apt-get >/dev/null;
 then
        echo "ERROR: apt-get not found. Cannot automatically install packages." >&2
        return 1
    fi

    sudo apt-get update

    # Install iproute2 if missing
    if ! command -v ip >/dev/null;
 then
        echo "Installing iproute2..."
        sudo apt-get install -y iproute2
    fi

    # Install Docker and Docker Compose if missing
    if ! command -v docker >/dev/null;
 then
        echo "Installing Docker Engine and Docker Compose..."
        sudo apt-get install -y ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        if sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; then
            sudo chmod a+r /etc/apt/keyrings/docker.asc
            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            echo "Adding current user to the 'docker' group..."
            sudo usermod -aG docker "$USER"
            echo "IMPORTANT: You may need to start a new shell session (or run 'newgrp docker') for group changes to take effect."
        else
            echo "ERROR: Failed to download Docker GPG key. Cannot install Docker automatically." >&2
            return 1
        fi
    fi
    return 0
}

# --- Discover Executable Paths ---
discover_commands() {
    local missing_any=0
    if ! command -v docker >/dev/null; then missing_any=1; fi
    if ! command -v ip >/dev/null; then missing_any=1; fi

    if [ "$missing_any" -eq 1 ]; then
        echo "Some required commands are missing."
        if install_prerequisites; then
            echo "--- Re-discovering commands after installation ---"
            if ! command -v docker >/dev/null || ! command -v ip >/dev/null; then
                echo "ERROR: Commands still missing after install attempt. Please install manually." >&2
                exit 1
            fi
        else
            echo "ERROR: Prerequisite installation failed. Please install manually." >&2
            exit 1
        fi
    fi
    # Check if user is in docker group now that we know docker is installed
    if ! docker info >/dev/null 2>&1;
 then
        echo "WARNING: Cannot run docker commands without sudo. Add user to 'docker' group:" >&2
        echo "         sudo usermod -aG docker $USER && newgrp docker" >&2
        echo "         You might need to log out and log back in for this to take effect." >&2
    fi
    echo "✅ All required commands found."
}


# --- VXLAN Functions ---
VXLAN_ID=100
VXLAN_PORT=4789
BRIDGE_NAME="br0"

vxlan_setup() {
    discover_commands
    local PEER_IP=$1
    local LOCAL_PHYS_IFACE=$2
    if [ -z "$PEER_IP" ] || [ -z "$LOCAL_PHYS_IFACE" ]; then
        echo "Usage: sudo $0 vxlan-setup <PEER_IP> <LOCAL_PHYS_IFACE>" >&2
        exit 1
    fi
    echo "--- Setting up VXLAN interface vxlan$VXLAN_ID ---"
    sudo ip link add vxlan"$VXLAN_ID" type vxlan id "$VXLAN_ID" remote "$PEER_IP" dstport "$VXLAN_PORT" dev "$LOCAL_PHYS_IFACE" || true
    sudo ip link set vxlan"$VXLAN_ID" up
    if ! ip link show "$BRIDGE_NAME" >/dev/null;
 then
        echo "WARNING: Bridge '$BRIDGE_NAME' not found. Creating it."
        sudo ip link add "$BRIDGE_NAME" type bridge
        sudo ip addr add 10.0.0.1/24 dev "$BRIDGE_NAME"
        sudo ip link set "$BRIDGE_NAME" up
    fi
    sudo ip link set vxlan"$VXLAN_ID" master "$BRIDGE_NAME"
    echo "✅ VXLAN setup complete on this host."
}

vxlan_cleanup() {
    discover_commands
    echo "--- Cleaning up VXLAN interface vxlan$VXLAN_ID ---"
    sudo ip link set vxlan"$VXLAN_ID" down 2>/dev/null || true
    sudo ip link del vxlan"$VXLAN_ID" 2>/dev/null || true
    echo "✅ VXLAN cleanup complete on this host."
}


# --- Docker Swarm Functions ---
swarm_init() {
    discover_commands
    local HOST_IP=$1
    if [ -z "$HOST_IP" ]; then
        echo "Usage: sudo $0 swarm-init <HOST_IP_TO_ADVERTISE>" >&2
        exit 1
    fi
    echo "--- Initializing Docker Swarm on this host ---"
    docker swarm init --advertise-addr "$HOST_IP"
    echo "✅ Swarm initialized. Copy the 'docker swarm join' command to other hosts."
}

swarm_join() {
    discover_commands
    local TOKEN=$1
    local MANAGER_IP=$2
    if [ -z "$TOKEN" ] || [ -z "$MANAGER_IP" ]; then
        echo "Usage: sudo $0 swarm-join <TOKEN> <MANAGER_IP:2377>" >&2
        exit 1
    fi
    echo "--- Joining Docker Swarm as a worker ---"
    docker swarm join --token "$TOKEN" "$MANAGER_IP"
    echo "✅ Host joined Swarm."
}

swarm_deploy() {
    discover_commands
    if [ ! -f "docker-compose.yml" ]; then
        echo "ERROR: docker-compose.yml not found. Please generate it using assignment5.sh first." >&2
        exit 1
    fi
    echo "--- Deploying application stack 'myapp' to Swarm ---"
    docker stack deploy -c docker-compose.yml myapp
    echo "✅ Stack 'myapp' deployed. Verify with 'docker service ls'."
}

swarm_cleanup_stack() {
    discover_commands
    echo "--- Removing deployed application stack 'myapp' ---"
    docker stack rm myapp || echo "Stack 'myapp' not found or already removed."
    echo "✅ Stack 'myapp' removed."
}

swarm_leave() {
    discover_commands
    echo "--- Leaving Docker Swarm ---"
    docker swarm leave --force
    echo "✅ Host left Swarm."
}

swarm_status() {
    discover_commands
    echo "--- Docker Swarm Status ---"
    if docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        docker node ls
    else
        echo "This host is not part of a Swarm."
    fi
}


# --- Main script logic ---
CMD=$1
shift || true 

case "$CMD" in
    vxlan-setup) vxlan_setup "$@";;
    vxlan-cleanup) vxlan_cleanup;; 
    swarm-init) swarm_init "$@";;
    swarm-join) swarm_join "$@";;
    swarm-deploy) swarm_deploy;; 
    swarm-cleanup-stack) swarm_cleanup_stack;; 
    swarm-leave) swarm_leave;; 
    swarm-status) swarm_status;; 
    *) 
        echo "Usage: sudo $0 {vxlan-setup|vxlan-cleanup|swarm-init|swarm-join|swarm-deploy|swarm-cleanup-stack|swarm-leave|swarm-status}" >&2
        exit 1
        ;; 
esac

exit 0