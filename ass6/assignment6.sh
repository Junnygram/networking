#!/bin/bash

# ===================================================================================
# Assignment 6 - Multi-Host Networking Helper Script
#
# This script provides helper functions for setting up multi-host networking
# using VXLAN and Docker Swarm. These commands must be run on EACH host
# participating in the multi-host setup.
#
# IMPORTANT: This script is a HELPER. It cannot fully automate a multi-host setup
#            from a single execution point. You must run appropriate commands
#            on each target host.
#
# Usage:
#   sudo ./assignment6.sh <command> <arguments...>
#
# Commands for VXLAN (Run on each host):
#   vxlan-setup <PEER_IP> <LOCAL_PHYS_IFACE>  - Sets up VXLAN interface and attaches to br0.
#   vxlan-cleanup                             - Tears down VXLAN setup.
#
# Commands for Docker Swarm:
#   swarm-init <HOST_IP>                      - Initializes Swarm on a manager node. (Run on Host A)
#   swarm-join <TOKEN> <MANAGER_IP>           - Joins Swarm as a worker node. (Run on Host B)
#   swarm-deploy                              - Deploys application stack using docker-compose.yml. (Run on Manager)
#   swarm-cleanup-stack                       - Removes deployed stack. (Run on Manager)
#   swarm-leave                               - Leaves the Swarm. (Run on Worker or Manager)
#
# ===================================================================================

set -e

# --- Prerequisites Check ---
ensure_docker_installed() {
    if ! command -v docker >/dev/null; then
        echo "ERROR: Docker is not installed. Please install Docker Engine on this host." >&2
        echo "See: https://docs.docker.com/engine/install/ubuntu/" >&2
        exit 1
    fi
    # Check if user is in docker group
    if ! docker info >/dev/null 2>&1; then
        echo "WARNING: Cannot run docker commands. Add your user to the 'docker' group:" >&2
        echo "         sudo usermod -aG docker $USER && newgrp docker" >&2
        echo "         You might need to log out and back in." >&2
        # Exit for now, as most subsequent commands will fail
        exit 1
    fi
}

ensure_iproute2_installed() {
    if ! command -v ip >/dev/null; then
        echo "ERROR: iproute2 is not installed. Please install it: sudo apt-get install iproute2" >&2
        exit 1
    fi
}

# --- VXLAN Functions ---

VXLAN_ID=100
VXLAN_PORT=4789
BRIDGE_NAME="br0" # Assumes br0 from Assignment 1 setup

vxlan_setup() {
    ensure_iproute2_installed
    local PEER_IP=$1
    local LOCAL_PHYS_IFACE=$2

    if [ -z "$PEER_IP" ] || [ -z "$LOCAL_PHYS_IFACE" ]; then
        echo "Usage: sudo $0 vxlan-setup <PEER_IP> <LOCAL_PHYS_IFACE>" >&2
        exit 1
    fi

    echo "--- Setting up VXLAN interface vxlan$VXLAN_ID ---"
    echo "  Peer IP: $PEER_IP"
    echo "  Local Physical Interface: $LOCAL_PHYS_IFACE"

    # Create VXLAN interface
    sudo ip link add vxlan"$VXLAN_ID" type vxlan id "$VXLAN_ID" remote "$PEER_IP" dstport "$VXLAN_PORT" dev "$LOCAL_PHYS_IFACE" || true
    sudo ip link set vxlan"$VXLAN_ID" up

    # Attach to bridge (assumes br0 is already created and up)
    echo "Attaching vxlan$VXLAN_ID to $BRIDGE_NAME"
    # Ensure bridge exists and is up
    if ! ip link show "$BRIDGE_NAME" >/dev/null; then
        echo "WARNING: Bridge '$BRIDGE_NAME' not found. Creating it."
        sudo ip link add "$BRIDGE_NAME" type bridge
        sudo ip addr add 10.0.0.1/24 dev "$BRIDGE_NAME" # Default IP for br0
        sudo ip link set "$BRIDGE_NAME" up
    fi
    sudo ip link set vxlan"$VXLAN_ID" master "$BRIDGE_NAME"

    echo "✅ VXLAN setup complete on this host."
    echo "   Verify with: ip link show vxlan$VXLAN_ID"
    echo "   Then try to ping between namespaces on different hosts (after setting up peer)."
}

vxlan_cleanup() {
    ensure_iproute2_installed
    echo "--- Cleaning up VXLAN interface vxlan$VXLAN_ID ---"
    sudo ip link set vxlan"$VXLAN_ID" down 2>/dev/null || true
    sudo ip link del vxlan"$VXLAN_ID" 2>/dev/null || true
    echo "✅ VXLAN cleanup complete on this host."
}


# --- Docker Swarm Functions ---

swarm_init() {
    ensure_docker_installed
    local HOST_IP=$1
    if [ -z "$HOST_IP" ]; then
        echo "Usage: sudo $0 swarm-init <HOST_IP>" >&2
        echo "  <HOST_IP> is the IP this manager node advertises." >&2
        exit 1
    fi
    echo "--- Initializing Docker Swarm on this host ---"
    docker swarm init --advertise-addr "$HOST_IP"
    echo "✅ Swarm initialized. Copy the 'docker swarm join' command to other hosts."
}

swarm_join() {
    ensure_docker_installed
    local TOKEN=$1
    local MANAGER_IP=$2
    if [ -z "$TOKEN" ] || [ -z "$MANAGER_IP" ]; then
        echo "Usage: sudo $0 swarm-join <TOKEN> <MANAGER_IP>" >&2
        echo "  <TOKEN> is from 'docker swarm init' or 'docker swarm join-token worker'." >&2
        echo "  <MANAGER_IP> is the manager's IP (e.g., 192.168.1.10:2377)." >&2
        exit 1
    fi
    echo "--- Joining Docker Swarm as a worker ---"
    docker swarm join --token "$TOKEN" "$MANAGER_IP":2377
    echo "✅ Host joined Swarm."
}

swarm_deploy() {
    ensure_docker_installed
    echo "--- Deploying application stack to Swarm ---"
    # This assumes docker-compose.yml and Dockerfiles are present
    # from Assignment 5 setup.
    if [ ! -f "docker-compose.yml" ]; then
        echo "ERROR: docker-compose.yml not found. Please generate it from Assignment 5." >&2
        exit 1
    fi
    # Also ensure images are built
    echo "Building images (if not already built)..."
    docker compose build || docker-compose build # Handle docker compose v1 vs v2
    echo "Deploying stack 'myapp'..."
    docker stack deploy -c docker-compose.yml myapp
    echo "✅ Stack 'myapp' deployed. Verify with 'docker service ls' and 'docker ps' on nodes."
}

swarm_cleanup_stack() {
    ensure_docker_installed
    echo "--- Removing deployed application stack 'myapp' ---"
    docker stack rm myapp
    echo "✅ Stack 'myapp' removed."
}

swarm_leave() {
    ensure_docker_installed
    echo "--- Leaving Docker Swarm ---"
    # Check if this node is a manager, force if so.
    if docker node inspect self --format '{{.ManagerStatus.Reachability}}' | grep -q "Reachable"; then
        echo "This node is a manager. Forcing leave."
        docker swarm leave --force
    else
        docker swarm leave
    fi
    echo "✅ Host left Swarm."
}

swarm_status() {
    ensure_docker_installed
    echo "--- Docker Swarm Status ---"
    if docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        echo "This host is part of a Swarm."
        docker node ls
    else
        echo "This host is not part of a Swarm."
    fi
}


# --- Main script logic ---
CMD=$1
shift || true # Shift arguments, allow for no arguments

case "$CMD" in
    vxlan-setup)
        vxlan_setup "$@"
        ;;
    vxlan-cleanup)
        vxlan_cleanup "$@"
        ;;
    swarm-init)
        swarm_init "$@"
        ;;
    swarm-join)
        swarm_join "$@"
        ;;
    swarm-deploy)
        swarm_deploy "$@"
        ;;
    swarm-cleanup-stack)
        swarm_cleanup_stack "$@"
        ;;
    swarm-leave)
        swarm_leave "$@"
        ;;
    swarm-status)
        swarm_status "$@"
        ;;
    *)
        echo "Usage: sudo $0 {vxlan-setup|vxlan-cleanup|swarm-init|swarm-join|swarm-deploy|swarm-cleanup-stack|swarm-leave|swarm-status}" >&2
        exit 1
        ;;
esac

exit 0
