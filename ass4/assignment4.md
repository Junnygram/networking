# Assignment 4: Advanced Networking

This assignment introduces advanced networking concepts: a service registry for service discovery, security policies using `iptables`, and architectural changes like load balancing and network segmentation.

This guide is broken into two parts. We will first script the Service Registry and Security Policies.

---

## ⚠️ Step 0: Prerequisites

**1. System Packages:**
Ensure `iptables` is installed (it should be on most Linux systems).

```bash
# For Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y iptables
```

**2. Python Packages:**
The service registry requires `Flask`.

```bash
pip3 install Flask
```

**3. Running Environment:**
This assignment assumes that:
*   The network from **Assignment 1** is running.
*   All the application services from **Assignment 2** are running.

---

## Part A: New Tools

### Task 4.1: Implement Simple Service Discovery

To avoid hardcoding IP addresses, we will create a central service registry. Other services can query this registry to discover where to find the services they depend on.

**1. Create `service-registry.py`:**
This is a simple Flask application that acts as our registry.

```python
#!/usr/bin/env python3
# service-registry.py

from flask import Flask, jsonify, request
import time

app = Flask(__name__)

# Use a simple dictionary as our in-memory service registry
services = {}

@app.route('/register', methods=['POST'])
def register_service():
    """Register a service's name, IP, and port."""
    data = request.json
    if not data or 'name' not in data or 'ip' not in data or 'port' not in data:
        return jsonify({"error": "Invalid registration data"}), 400
        
    service_name = data['name']
    services[service_name] = {
        'ip': data['ip'],
        'port': data['port'],
        'registered_at': time.time(),
        'health': 'unknown' # A real registry would have a health check mechanism
    }
    print(f"Registered service: {service_name} at {data['ip']}:{data['port']}")
    return jsonify({"status": "registered", "service": service_name})

@app.route('/discover/<service_name>', methods=['GET'])
def discover_service(service_name):
    """Discover a service by name."""
    if service_name in services:
        return jsonify(services[service_name])
    else:
        return jsonify({"error": "Service not found"}), 404

@app.route('/services', methods=['GET'])
def list_services():
    """List all registered services."""
    return jsonify(services)

@app.route('/deregister/<service_name>', methods=['DELETE'])
def deregister_service(service_name):
    """Deregister a service."""
    if service_name in services:
        del services[service_name]
        print(f"Deregistered service: {service_name}")
        return jsonify({"status": "deregistered"})
    else:
        return jsonify({"error": "Service not found"}), 404

if __name__ == '__main__':
    # This service runs on the host or in a dedicated namespace.
    # For simplicity, we can run it on the host.
    app.run(host='0.0.0.0', port=8500)
```

**2. How to Use:**
You would modify your applications (e.g., `api-gateway.py`) to first make a request to `http://<registry_ip>:8500/discover/product-service` to get the IP and port, instead of using a hardcoded URL.

---

### Task 4.3: Implement Network Security Policies

We will use `iptables` to create a basic firewall, restricting traffic between our services to only what is necessary. This is a fundamental security practice.

**Create a `security-policies.sh` script:**
This script applies a set of restrictive `iptables` rules.

```bash
#!/bin/bash
# security-policies.sh

echo "Applying network security policies..."

# By default, drop all traffic being forwarded across the bridge.
# This is a 'default deny' policy. We will add specific 'allow' rules.
sudo iptables -P FORWARD DROP

# --- Allow Rules ---

# 1. Allow API Gateway (10.0.0.20) to talk to Product Service (10.0.0.30) and Order Service (10.0.0.40)
sudo iptables -A FORWARD -s 10.0.0.20 -d 10.0.0.30 -p tcp --dport 5000 -j ACCEPT
sudo iptables -A FORWARD -s 10.0.0.20 -d 10.0.0.40 -p tcp --dport 5000 -j ACCEPT

# 2. Allow Product Service (10.0.0.30) to talk to Redis (10.0.0.50)
sudo iptables -A FORWARD -s 10.0.0.30 -d 10.0.0.50 -p tcp --dport 6379 -j ACCEPT

# 3. Allow Order Service (10.0.0.40) to talk to PostgreSQL (10.0.0.60)
sudo iptables -A FORWARD -s 10.0.0.40 -d 10.0.0.60 -p tcp --dport 5432 -j ACCEPT

# 4. Allow Nginx LB (10.0.0.10) to talk to the API Gateway (10.0.0.20)
sudo iptables -A FORWARD -s 10.0.0.10 -d 10.0.0.20 -p tcp --dport 3000 -j ACCEPT

# 5. Allow return traffic for established connections. This is crucial.
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 6. Allow all services to access the internet (DNS and HTTP/S)
sudo iptables -A FORWARD -s 10.0.0.0/24 -p udp --dport 53 -j ACCEPT
sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 53 -j ACCEPT
sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 80 -j ACCEPT
sudo iptables -A FORWARD -s 10.0.0.0/24 -p tcp --dport 443 -j ACCEPT

# 7. Log dropped packets for debugging (optional, but very useful)
sudo iptables -A FORWARD -j LOG --log-prefix "FW_DROPPED: " --log-level 4

echo "✅ Security policies applied successfully!"
```
A corresponding cleanup script is required to remove these rules and reset the default policy.

**Deliverable:** A document explaining the purpose of each security rule.

---
---

## Part B: Major Architectural Changes

**Note:** The following tasks require modifying the base network and service deployment from Assignments 1 & 2.

### Task 4.2: Implement Round-Robin Load Balancing

To handle more traffic, you can run multiple instances of a service (e.g., `product-service`) and have the `api-gateway` distribute requests among them.

**1. Create more Product Service instances:**
You would need to create new namespaces and IPs for them (e.g., `product-service-2` at `10.0.0.31`, `product-service-3` at `10.0.0.32`).

**2. Update the API Gateway:**
Modify `api-gateway.py` to use a load-balancing strategy, like round-robin.

```python
# Example of a simple round-robin load balancer in api-gateway.py
import itertools

class LoadBalancer:
    def __init__(self, backends):
        # A generator that cycles through the list of backends indefinitely
        self.backends = itertools.cycle(backends)
    
    def get_next_backend(self):
        return next(self.backends)

# Discover backends from the service registry or use a static list
PRODUCT_SERVICE_BACKENDS = [
    "http://10.0.0.30:5000",
    "http://10.0.0.31:5000",
    "http://10.0.0.32:5000",
]
product_lb = LoadBalancer(PRODUCT_SERVICE_BACKENDS)

# In your route, get the next available backend
# url = product_lb.get_next_backend()
# response = requests.get(f"{url}/products")
```

**Deliverable:** A working load balancer with logs showing that requests are distributed across multiple instances.

---

### Task 4.4: Implement Network Isolation with Multiple Bridges

For better security and organization, you can create separate networks (bridges) for different application tiers (e.g., frontend, backend, database).

**1. Create new bridges:**
```bash
# Frontend network for LB and API Gateway
sudo ip link add br-frontend type bridge
sudo ip addr add 172.20.0.1/24 dev br-frontend
sudo ip link set br-frontend up

# Backend network for application services
sudo ip link add br-backend type bridge
sudo ip addr add 172.21.0.1/24 dev br-backend
sudo ip link set br-backend up

# Database network for data stores
sudo ip link add br-database type bridge
sudo ip addr add 172.22.0.1/24 dev br-database
sudo ip link set br-database up
```

**2. Reconfigure Services:**
This would involve:
*   Moving service veth pairs to the appropriate new bridges.
*   Giving services in different networks different IP ranges (e.g., `nginx-lb` on `172.20.0.10`).
*   Making the `api-gateway` multi-homed, with network interfaces on both `br-frontend` and `br-backend` so it can talk to both.
*   Configuring routing between these networks, likely on the host or in a dedicated "router" namespace.

**Deliverable:** A multi-network topology with documented routing rules.

```