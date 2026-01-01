#!/bin/bash

# ===================================================================================
# Assignment 4 (Part B) - Segmented Network Setup Script
#
# This script builds a segmented network with three separate bridges for frontend,
# backend, and database tiers. It also configures a multi-homed API Gateway
# to route traffic between the frontend and backend networks.
#
# Usage:
#   sudo ./assignment4-network.sh         # Creates the entire network
#   sudo ./assignment4-network.sh cleanup   # Tears down the entire network
# ===================================================================================

set -e

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi


# --- Network Definitions ---
declare -A BRIDGES
BRIDGES=(
    ["br-frontend"]="172.20.0.1/24"
    ["br-backend"]="172.21.0.1/24"
    ["br-database"]="172.22.0.1/24"
)

# --- Namespace to Network Mapping ---
declare -A NS_NET_MAP
NS_NET_MAP=(
    ["nginx-lb"]="frontend"
    ["api-gateway"]="frontend" # Primary network, will also connect to backend
    ["product-service-1"]="backend"
    ["product-service-2"]="backend" # Replica for load balancing
    ["product-service-3"]="backend" # Replica for load balancing
    ["order-service"]="backend"
    ["redis-cache"]="database"
    ["postgres-db"]="database"
)

# --- IP Address Assignments ---
declare -A NS_IP_MAP
NS_IP_MAP=(
    ["nginx-lb"]="172.20.0.10/24"
    ["api-gateway-frontend"]="172.20.0.20/24" # IP on the frontend bridge
    ["api-gateway-backend"]="172.21.0.20/24"  # IP on the backend bridge
    ["product-service-1"]="172.21.0.30/24"
    ["product-service-2"]="172.21.0.31/24"
    ["product-service-3"]="172.21.0.32/24"
    ["order-service"]="172.21.0.40/24"
    ["redis-cache"]="172.22.0.50/24"
    ["postgres-db"]="172.22.0.60/24"
)

# --- Main Cleanup Function ---
cleanup() {
    echo "--- Tearing down all networks and namespaces ---"

    # Delete all namespaces
    for ns in "${!NS_NET_MAP[@]}"; do
        echo "Deleting namespace: $ns"
        sudo ip netns delete "$ns" 2>/dev/null || true
    done

    # Delete all bridges
    for br in "${!BRIDGES[@]}"; do
        echo "Deleting bridge: $br"
        sudo ip link set "$br" down 2>/dev/null || true
        sudo ip link delete "$br" 2>/dev/null || true
    done

    # Disable IP forwarding
    echo "Disabling IP forwarding"
    sudo sysctl -w net.ipv4.ip_forward=0 2>/dev/null || true

    echo "✅ Network cleanup complete."
}

# --- Main Setup Function ---
setup() {
    echo "--- Installing prerequisites ---"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3.12-venv curl iproute2 redis-server nginx
    echo "Prerequisite installation complete."

    echo "--- Building segmented network infrastructure ---"

    # Enable IP forwarding on the host to route between bridges
    echo "Enabling IP forwarding on host..."
    sudo sysctl -w net.ipv4.ip_forward=1

    # Create all bridges
    for br in "${!BRIDGES[@]}"; do
        ip="${BRIDGES[$br]}"
        echo "Creating bridge '$br' with IP $ip..."
        sudo ip link add "$br" type bridge
        sudo ip addr add "$ip" dev "$br"
        sudo ip link set "$br" up
    done

    # Create namespaces and simple veth pairs
    for ns in "${!NS_NET_MAP[@]}"; do
        net_suffix="${NS_NET_MAP[$ns]}"
        bridge="br-$net_suffix"
        
        # Skip api-gateway, as it has a special setup
        if [ "$ns" == "api-gateway" ]; then continue; fi

        echo "--- Configuring namespace: $ns ---"
        sudo ip netns add "$ns"

        # Create a unique, short name for the veth pair.
        # Substitutions are applied, then the result is truncated to 7 chars to be safe.
        short_name=$(echo "$ns" | sed 's/product-service/ps/' | sed 's/postgres/pg/' | sed 's/gateway/gw/' | sed 's/nginx/ngx/' | sed 's/-//g')
        short_name=${short_name:0:7}
        veth_ns="veth-${short_name}"
        veth_br="${veth_ns}-br"
        
        sudo ip link add "$veth_ns" type veth peer name "$veth_br"

        # Attach to bridge and move to namespace
        sudo ip link set "$veth_br" master "$bridge"
        sudo ip link set "$veth_br" up
        sudo ip link set "$veth_ns" netns "$ns"

        # Configure interface inside namespace
        ip="${NS_IP_MAP[$ns]}"
        gateway_ip=$(echo "${BRIDGES[$bridge]}" | cut -d'/' -f1)
        sudo ip netns exec "$ns" ip addr add "$ip" dev "$veth_ns"
        sudo ip netns exec "$ns" ip link set dev "$veth_ns" up
        sudo ip netns exec "$ns" ip link set dev lo up
        sudo ip netns exec "$ns" ip route add default via "$gateway_ip"
    done

    # --- Special setup for the multi-homed API Gateway ---
    echo "--- Configuring multi-homed namespace: api-gateway ---"
    sudo ip netns add api-gateway
    
    # 1. Frontend veth pair
    sudo ip link add veth-api-fe type veth peer name veth-api-fe-br
    sudo ip link set veth-api-fe-br master br-frontend
    sudo ip link set veth-api-fe-br up
    sudo ip link set veth-api-fe netns api-gateway
    sudo ip netns exec api-gateway ip addr add "${NS_IP_MAP[api-gateway-frontend]}" dev veth-api-fe
    sudo ip netns exec api-gateway ip link set dev veth-api-fe up
    
    # 2. Backend veth pair
    sudo ip link add veth-api-be type veth peer name veth-api-be-br
    sudo ip link set veth-api-be-br master br-backend
    sudo ip link set veth-api-be-br up
    sudo ip link set veth-api-be netns api-gateway
    sudo ip netns exec api-gateway ip addr add "${NS_IP_MAP[api-gateway-backend]}" dev veth-api-be
    sudo ip netns exec api-gateway ip link set dev veth-api-be up

    # 3. Configure default route and routing policies inside api-gateway
    # The default gateway will be on the frontend network
    frontend_gw=$(echo "${BRIDGES[br-frontend]}" | cut -d'/' -f1)
    sudo ip netns exec api-gateway ip route add default via "$frontend_gw"
    
    sudo ip netns exec api-gateway ip link set dev lo up
    
    echo "✅ Segmented network setup complete."
}


# --- Main script logic ---
if [ "" == "cleanup" ]; then
    cleanup
else
    # Run cleanup first to ensure a clean state
    cleanup
    setup
fi

exit 0
