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
    ["backend-db-router-backend"]="172.21.0.100/24"
    ["backend-db-router-database"]="172.22.0.100/24"
)

# --- Main Cleanup Function ---
cleanup() {
    echo "--- Tearing down all networks and namespaces ---"

    # Forcefully kill any lingering processes that could hold namespaces open
    echo "Stopping any lingering postgres or redis processes..."
    sudo pkill -9 -f "postgres" 2>/dev/null || true
    sudo pkill -9 -f "redis-server" 2>/dev/null || true
    sleep 1 # Give processes a moment to die


    # Delete all namespaces
    for ns in "${!NS_NET_MAP[@]}"; do
        echo "Deleting namespace: $ns"
        sudo ip netns delete "$ns" 2>/dev/null || true

        # Also delete the veth pairs associated with the namespace
        short_name=$(echo "$ns" | sed 's/product-service/ps/' | sed 's/postgres/pg/' | sed 's/gateway/gw/' | sed 's/nginx/ngx/' | sed 's/-//g')
        short_name=${short_name:0:7}
        veth_br="veth-${short_name}-br"
        sudo ip link delete "$veth_br" 2>/dev/null || true
    done

    # Manually delete special veth pairs
    sudo ip link delete "veth-api-fe-br" 2>/dev/null || true
    sudo ip link delete "veth-api-be-br" 2>/dev/null || true
    sudo ip link delete "veth-bdr-be-br" 2>/dev/null || true
    sudo ip link delete "veth-bdr-db-br" 2>/dev/null || true

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

# --- Function to flush all iptables rules ---
flush_iptables() {
    echo "--- Flushing all iptables rules and setting policy to ACCEPT ---"
    if command -v iptables >/dev/null; then
        # Flush FORWARD chain for inter-container traffic
        sudo iptables -P FORWARD ACCEPT 2>/dev/null || true
        sudo iptables -F FORWARD 2>/dev/null || true
        # Flush INPUT chain for container-to-host traffic (for PostgreSQL)
        sudo iptables -P INPUT ACCEPT 2>/dev/null || true
        sudo iptables -F INPUT 2>/dev/null || true
        echo "✅ iptables FORWARD and INPUT chains flushed."
    else
        echo "iptables command not found, skipping flush."
    fi
}

# --- Main Setup Function ---
setup() {
    # Ensure a clean state before starting
    flush_iptables

    echo "--- Installing prerequisites ---"
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-pip python3.12-venv curl iproute2 redis-server nginx postgresql
    echo "Prerequisite installation complete."

    # --- Configure and Start Host-level PostgreSQL ---
    echo "--- Configuring host PostgreSQL server ---"
    
    # Overwrite config files to allow connections from the container networks
    # Detect Postgres version and config directory
    PG_CONF_DIR=$(ls -d /etc/postgresql/*/main | head -n 1)
    if [ -z "$PG_CONF_DIR" ]; then
        echo "Could not detect PostgreSQL configuration directory."
        exit 1
    fi
    echo "Detected PostgreSQL configuration in: $PG_CONF_DIR"

    # Backup original config if not already backed up
    if [ ! -f "$PG_CONF_DIR/postgresql.conf.orig" ]; then
        cp "$PG_CONF_DIR/postgresql.conf" "$PG_CONF_DIR/postgresql.conf.orig"
    fi

    # Check if original config is corrupted (too small or contains 'include postgresql.conf.orig')
    if grep -q "include 'postgresql.conf.orig'" "$PG_CONF_DIR/postgresql.conf.orig" || [ $(stat -c%s "$PG_CONF_DIR/postgresql.conf.orig") -lt 100 ]; then
        echo "⚠️  Detected corrupted backup config. Attempting to restore from sample..."
        PG_VER=$(basename $(dirname $(dirname $PG_CONF_DIR)))
        SAMPLE_CONF="/usr/share/postgresql/$PG_VER/postgresql.conf.sample"
        if [ -f "$SAMPLE_CONF" ]; then
             cp "$SAMPLE_CONF" "$PG_CONF_DIR/postgresql.conf.orig"
             echo "✅ Restored postgresql.conf.orig from sample."
        else
             echo "❌ Could not find sample config at $SAMPLE_CONF. Please reinstall postgresql."
             exit 1
        fi
    fi

    # Overwrite config files to allow connections from the container networks
    cat <<EOF > "$PG_CONF_DIR/postgresql.conf"
include 'postgresql.conf.orig'
listen_addresses = '*'
EOF
    cat <<EOF > "$PG_CONF_DIR/pg_hba.conf"
# Allow md5 password auth for all network connections from any source
host    all             all             0.0.0.0/0               md5
# Allow local connections for admin tasks
local   all             postgres                                peer
EOF

    # Restart the service to apply changes and ensure it's running
    echo "Restarting PostgreSQL service on host..."
    sudo systemctl restart postgresql

    # Create the user and database
    echo "Creating database user and 'orders' database..."
    # Ensure password is set correctly even if user exists
    sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres'"
    sudo -u postgres psql -c "CREATE DATABASE orders" || echo "Database 'orders' already exists or could not be created."
    
    echo "Creating 'orders' table..."
    sudo -u postgres psql -d orders -c "CREATE TABLE IF NOT EXISTS orders (id SERIAL PRIMARY KEY, data JSONB);"


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
        
        # Skip api-gateway and the router, as they have a special setup
        if [ "$ns" == "api-gateway" ] || [ "$ns" == "backend-db-router" ]; then continue; fi

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

        # If it's a backend service, add a route to the database network via our router
        if [ "$net_suffix" == "backend" ]; then
            echo "Adding route to database network for $ns..."
            sudo ip netns exec "$ns" ip route add 172.22.0.0/24 via "${NS_IP_MAP[backend-db-router-backend]%%/*}"
        fi

        # If it's the redis service (database network), add a return route to backend network via router
        if [ "$ns" == "redis-cache" ]; then
             echo "Adding return route to backend network for $ns..."
             sudo ip netns exec "$ns" ip route add 172.21.0.0/24 via "${NS_IP_MAP[backend-db-router-database]%%/*}"
        fi
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
    
    # --- Special setup for the multi-homed Backend-DB Router ---
    echo "--- Configuring multi-homed namespace: backend-db-router ---"
    sudo ip netns add backend-db-router
    
    # 1. Backend veth pair
    sudo ip link add veth-bdr-be type veth peer name veth-bdr-be-br
    sudo ip link set veth-bdr-be-br master br-backend
    sudo ip link set veth-bdr-be-br up
    sudo ip link set veth-bdr-be netns backend-db-router
    sudo ip netns exec backend-db-router ip addr add "${NS_IP_MAP[backend-db-router-backend]}" dev veth-bdr-be
    sudo ip netns exec backend-db-router ip link set dev veth-bdr-be up
    
    # 2. Database veth pair
    sudo ip link add veth-bdr-db type veth peer name veth-bdr-db-br
    sudo ip link set veth-bdr-db-br master br-database
    sudo ip link set veth-bdr-db-br up
    sudo ip link set veth-bdr-db netns backend-db-router
    sudo ip netns exec backend-db-router ip addr add "${NS_IP_MAP[backend-db-router-database]}" dev veth-bdr-db
    sudo ip netns exec backend-db-router ip link set dev veth-bdr-db up

    # 3. Enable IP forwarding within the router namespace
    sudo ip netns exec backend-db-router sysctl -w net.ipv4.ip_forward=1 > /dev/null
    sudo ip netns exec backend-db-router ip link set dev lo up
    
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
