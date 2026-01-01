#!/bin/bash

# This script automates the creation and cleanup of a multi-service virtual network
# using Linux namespaces, a bridge, and veth pairs. It is idempotent.
# This version is updated to fix a cleanup issue related to bind-mounted resolv.conf files.

# Exit immediately if a command exits with a non-zero status.
set -e
# Print each command to stdout before executing it, for debugging.
set -x

# --- Resource Definitions ---
NAMESPACES=(
    "api-gateway"
    "postgres-db"
    "nginx-lb"
    "order-service"
    "product-service"
    "redis-cache"
)

# Use short names for veth interfaces to avoid exceeding the 15-character limit.
SHORT_NAMES=(
    "api"
    "pg"
    "lb"
    "ord"
    "prod"
    "cache"
)

IPS=(
    "10.0.0.20/24" # api-gateway
    "10.0.0.60/24" # postgres-db
    "10.0.0.10/24" # nginx-lb
    "10.0.0.40/24" # order-service
    "10.0.0.30/24" # product-service
    "10.0.0.50/24" # redis-cache
)

BRIDGE_NAME="br0"
BRIDGE_IP="10.0.0.1/24"
BRIDGE_SUBNET="10.0.0.0/24"

# --- Dynamically determine the default host interface for NAT ---
DEFAULT_IFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}')

# --- Cleanup Function ---
# This function is called first to remove any leftover resources from previous runs.
cleanup() {
    echo "--- Starting cleanup of network resources ---"
    
    # Delete the NAT rule added during setup.
    echo "Deleting NAT rule..."
    sudo iptables -t nat -D POSTROUTING -s "$BRIDGE_SUBNET" -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null || true
    
    # Clean up namespaces.
    for ns in "${NAMESPACES[@]}"; do
        echo "Deleting namespace: $ns"
        sudo ip netns delete "$ns" 2>/dev/null || true
    done
    
    # Delete the network bridge.
    echo "Deleting bridge: $BRIDGE_NAME"
    sudo ip link delete "$BRIDGE_NAME" type bridge 2>/dev/null || true
    
    echo "--- Cleanup complete ---"
}

# --- Setup Function ---
# This function builds the entire network stack.
setup() {
    echo "--- Starting network setup ---"

    # Enable IP forwarding on the host to allow it to act as a router.
    echo "Enabling IP forwarding..."
    sudo sysctl -w net.ipv4.ip_forward=1

    # Add the NAT (Masquerade) rule to allow traffic from namespaces to the internet.
    echo "Adding NAT rule for internet access..."
    sudo iptables -t nat -A POSTROUTING -s "$BRIDGE_SUBNET" -o "$DEFAULT_IFACE" -j MASQUERADE

    # Create and configure the central network bridge.
    echo "Creating and configuring bridge: $BRIDGE_NAME"
    sudo ip link add "$BRIDGE_NAME" type bridge
    sudo ip addr add "$BRIDGE_IP" dev "$BRIDGE_NAME"
    sudo ip link set "$BRIDGE_NAME" up

    # Allow traffic to be forwarded to and from the bridge interface
    echo "Adding iptables rules to allow forwarding on the bridge..."
    sudo iptables -A FORWARD -i "$BRIDGE_NAME" -j ACCEPT
    sudo iptables -A FORWARD -o "$BRIDGE_NAME" -j ACCEPT

    # Loop through the defined services to create and configure each one.
    for i in "${!NAMESPACES[@]}"; do
        NS_NAME=${NAMESPACES[$i]}
        SHORT_NAME=${SHORT_NAMES[$i]}
        IP_ADDR=${IPS[$i]}
        VETH_NS="veth-$SHORT_NAME"
        VETH_BR="${VETH_NS}-br"

        echo "--- Setting up namespace: $NS_NAME (veths: $VETH_NS, $VETH_BR) ---"
        
        # Create the isolated network namespace.
        sudo ip netns add "$NS_NAME"
        
        # Create the virtual Ethernet (veth) pair using the safe, shortened names.
        sudo ip link add "$VETH_NS" type veth peer name "$VETH_BR"
        
        # Attach one end of the veth pair to the bridge.
        sudo ip link set "$VETH_BR" master "$BRIDGE_NAME"
        
        # Move the other end of the veth pair into the namespace.
        sudo ip link set "$VETH_NS" netns "$NS_NAME"
        
        # Configure the network interface inside the namespace (IP address, bring it up).
        sudo ip netns exec "$NS_NAME" ip addr add "$IP_ADDR" dev "$VETH_NS"
        sudo ip netns exec "$NS_NAME" ip link set dev "$VETH_NS" up
        sudo ip netns exec "$NS_NAME" ip link set dev lo up # Bring up the loopback interface.
        
        # Add a default route inside the namespace to point all outbound traffic to the bridge.
        sudo ip netns exec "$NS_NAME" ip route add default via "$(echo "$BRIDGE_IP" | cut -d'/' -f1)"
        
        # Bring up the bridge-facing side of the veth pair.
        sudo ip link set dev "$VETH_BR" up
    done

    echo "--- Network setup complete ---"
}

# --- Main Execution ---
# First, run cleanup to ensure a clean slate. Then, run setup.
cleanup
setup

# --- Verification Step ---
# Finally, test that everything works by pinging a public domain from each namespace.
# DNS is configured ephemerally for this command only, to avoid cleanup issues.
echo ""
echo "--- Verifying internet connectivity (including DNS) from each namespace ---"
for ns in "${NAMESPACES[@]}"; do
    echo "--> Pinging google.com from namespace: $ns"
    # Execute a sub-shell in the namespace to set DNS and then ping.
    if sudo ip netns exec "$ns" bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf && ping -c 2 -W 5 google.com" &> /dev/null; then
        echo "    ✅ Ping successful!"
    else
        echo "    ❌ Ping FAILED."
    fi
done

echo "Script finished successfully."