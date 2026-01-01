# Assignment 4: Manual Advanced Networking Commands

This document provides the manual commands for the two major parts of Assignment 4:
*   **Part A:** Enhancing the original flat network with a Service Registry and `iptables` security policies.
*   **Part B:** Building the new, advanced architecture with network segmentation and load balancing.

---

## Part A: Enhancements for the Flat Network

These commands assume you have the flat network from Assignment 1 running, with services deployed as in Assignment 2.

### 1. Service Registry

This creates and runs a simple service discovery registry.

**Step 1: Create the `service-registry.py` file**
```bash
cat << 'EOF' > service-registry.py
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

if __name__ == '__main__':
    print("Service Registry running on http://0.0.0.0:8500", file=sys.stderr)
    app.run(host='0.0.0.0', port=8500, debug=False)
EOF
```

**Step 2: Run the Service Registry**
This can be run on the host machine. You will need to have Flask installed (`pip3 install Flask`).
```bash
python3 service-registry.py &
```

### 2. Network Security Policies

These commands apply a restrictive "default deny" firewall policy to the `br0` bridge.

**Step 1: Apply the Policies**
```bash
# Set the default policy for the FORWARD chain to DROP.
# This blocks any traffic not explicitly allowed.
sudo iptables -P FORWARD DROP

# Allow traffic for connections that are already established or related.
# This is crucial for return traffic to work.
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow specific service-to-service communication paths
sudo iptables -A FORWARD -s 10.0.0.10 -d 10.0.0.20 -p tcp --dport 3000 -j ACCEPT # nginx -> api-gateway
sudo iptables -A FORWARD -s 10.0.0.20 -d 10.0.0.30 -p tcp --dport 5000 -j ACCEPT # api-gateway -> product-service
sudo iptables -A FORWARD -s 10.0.0.20 -d 10.0.0.40 -p tcp --dport 5000 -j ACCEPT # api-gateway -> order-service
sudo iptables -A FORWARD -s 10.0.0.30 -d 10.0.0.50 -p tcp --dport 6379 -j ACCEPT # product-service -> redis
sudo iptables -A FORWARD -s 10.0.0.40 -d 10.0.0.1 -p tcp --dport 5432 -j ACCEPT  # order-service -> postgres (on host)

# Allow outbound internet access for all services
sudo iptables -A FORWARD -s 10.0.0.0/24 -p udp --dport 53 -j ACCEPT # DNS
sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 53 -j ACCEPT # DNS
sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 80 -j ACCEPT  # HTTP
sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 443 -j ACCEPT # HTTPS

# Log any packets that are dropped (useful for debugging)
sudo iptables -A FORWARD -j LOG --log-prefix "FW_DROPPED: " --log-level 4
```

**Step 2: View the Policies**
```bash
sudo iptables -L FORWARD -v -n --line-numbers
```

**Step 3: Remove the Policies**
```bash
# Flush all rules from the FORWARD chain
sudo iptables -F FORWARD

# Set the default policy back to ACCEPT
sudo iptables -P FORWARD ACCEPT
```

---

## Part B: Manual Setup for Segmented Network & Load Balancing

This is a comprehensive set of commands to build the advanced architecture from `ass4/modified_setup/` from scratch.

### 1. Create the Segmented Network

**Step 1: Enable IP Forwarding**
```bash
sudo sysctl -w net.ipv4.ip_forward=1
```

**Step 2: Create the Three Bridges**
```bash
# Frontend Bridge
sudo ip link add br-frontend type bridge
sudo ip addr add 172.20.0.1/24 dev br-frontend
sudo ip link set br-frontend up

# Backend Bridge
sudo ip link add br-backend type bridge
sudo ip addr add 172.21.0.1/24 dev br-backend
sudo ip link set br-backend up

# Database Bridge
sudo ip link add br-database type bridge
sudo ip addr add 172.22.0.1/24 dev br-database
sudo ip link set br-database up
```

**Step 3: Create Namespaces and Connect Them**
Create namespaces for Nginx, the three product service replicas, the order service, Redis, and PostgreSQL. Then, connect them to the appropriate bridges.

*(This is a repetitive process, showing one example for each bridge)*

**Example: `nginx-lb` on `br-frontend`**
```bash
NS="nginx-lb"
VETH_NS="veth-ngx"
VETH_BR="veth-ngx-br"
IP="172.20.0.10/24"
GW="172.20.0.1"

sudo ip netns add $NS
sudo ip link add $VETH_NS type veth peer name $VETH_BR
sudo ip link set $VETH_BR master br-frontend
sudo ip link set $VETH_BR up
sudo ip link set $VETH_NS netns $NS
sudo ip netns exec $NS ip addr add $IP dev $VETH_NS
sudo ip netns exec $NS ip link set dev $VETH_NS up
sudo ip netns exec $NS ip link set dev lo up
sudo ip netns exec $NS ip route add default via $GW
```

**Example: `product-service-1` on `br-backend`**
```bash
NS="product-service-1"
VETH_NS="veth-ps1"
VETH_BR="veth-ps1-br"
IP="172.21.0.30/24"
GW="172.21.0.1"

sudo ip netns add $NS
sudo ip link add $VETH_NS type veth peer name $VETH_BR
sudo ip link set $VETH_BR master br-backend
sudo ip link set $VETH_BR up
sudo ip link set $VETH_NS netns $NS
sudo ip netns exec $NS ip addr add $IP dev $VETH_NS
sudo ip netns exec $NS ip link set dev $VETH_NS up
sudo ip netns exec $NS ip link set dev lo up
sudo ip netns exec $NS ip route add default via $GW
```

**Step 4: Special Setup for Multi-Homed `api-gateway`**
The API gateway needs to connect to both the frontend and backend bridges.
```bash
sudo ip netns add api-gateway

# Frontend connection
sudo ip link add veth-api-fe type veth peer name veth-api-fe-br
sudo ip link set veth-api-fe-br master br-frontend
sudo ip link set veth-api-fe-br up
sudo ip link set veth-api-fe netns api-gateway
sudo ip netns exec api-gateway ip addr add 172.20.0.20/24 dev veth-api-fe
sudo ip netns exec api-gateway ip link set dev veth-api-fe up

# Backend connection
sudo ip link add veth-api-be type veth peer name veth-api-be-br
sudo ip link set veth-api-be-br master br-backend
sudo ip link set veth-api-be-br up
sudo ip link set veth-api-be netns api-gateway
sudo ip netns exec api-gateway ip addr add 172.21.0.20/24 dev veth-api-be
sudo ip netns exec api-gateway ip link set dev veth-api-be up

# Set default route to go out the frontend
sudo ip netns exec api-gateway ip route add default via 172.20.0.1
sudo ip netns exec api-gateway ip link set dev lo up
```

### 2. Deploy the Services

Create the application files (note the new load-balancing API gateway and updated IPs) and run them in their namespaces.

*(The commands to create the files are omitted for brevity but are present in `ass4/modified_setup/assignment4-services.sh`. The key change is in `api-gateway-lb.py`)*

**Run the services:**
```bash
# Start Redis and Nginx
sudo ip netns exec redis-cache redis-server --bind 0.0.0.0 --port 6379 --daemonize yes --protected-mode no
sudo ip netns exec nginx-lb nginx -c /path/to/your/new/nginx.conf

# Start application services (in separate terminals)
sudo ip netns exec api-gateway python3 api-gateway-lb.py
sudo ip netns exec order-service python3 order-service.py
sudo ip netns exec product-service-1 python3 product-service.py
sudo ip netns exec product-service-2 python3 product-service.py
sudo ip netns exec product-service-3 python3 product-service.py
```
This completes the manual setup of the advanced, segmented architecture.
