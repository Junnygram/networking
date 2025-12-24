# Container Networking Week-Long Project

## Building a Complete Multi-Service Application Infrastructure from Scratch

### Project Overview

You will build a complete containerized microservices application infrastructure using **only Linux primitives** (no Docker initially), then migrate it to Docker, and finally implement advanced networking features. This project simulates a real-world e-commerce platform with multiple services.

**Duration:** 5-7 days  
**Difficulty:** Advanced  
**Prerequisites:** Linux command line, basic networking knowledge, Python/Node.js basics

---

## Learning Objectives

By completing this project, you will:

1. Master Linux network namespaces and isolation
2. Implement virtual networking with veth pairs and bridges
3. Configure NAT and iptables for routing and security
4. Build overlay networks for multi-host communication
5. Implement service discovery and load balancing
6. Create monitoring and debugging solutions
7. Migrate from raw Linux to container runtimes
8. Document and present your infrastructure

---

## System Architecture

You will build this complete system:

```
┌─────────────────────────────────────────────────────────────────┐
│                    E-COMMERCE PLATFORM                          │
└─────────────────────────────────────────────────────────────────┘

External Users
     │
     ↓
┌─────────────────────────────────────────────────────────────────┐
│ EDGE LAYER                                                      │
│  ┌──────────────┐      ┌──────────────┐                        │
│  │  Load        │      │   API        │                        │
│  │  Balancer    │─────▶│   Gateway    │                        │
│  │  (nginx)     │      │   (Node.js)  │                        │
│  └──────────────┘      └──────┬───────┘                        │
└────────────────────────────────┼────────────────────────────────┘
                                 │
┌────────────────────────────────┼────────────────────────────────┐
│ APPLICATION LAYER              │                                │
│                    ┌───────────┴──────────┐                     │
│                    │                      │                     │
│         ┌──────────▼─────────┐ ┌─────────▼────────┐            │
│         │   Product Service  │ │   Order Service  │            │
│         │   (Python Flask)   │ │   (Python Flask) │            │
│         └──────────┬─────────┘ └─────────┬────────┘            │
└────────────────────┼───────────────────────┼────────────────────┘
                     │                       │
┌────────────────────┼───────────────────────┼────────────────────┐
│ DATA LAYER         │                       │                    │
│         ┌──────────▼─────────┐  ┌─────────▼────────┐           │
│         │   Redis Cache      │  │   PostgreSQL     │           │
│         │   (Session Store)  │  │   (Database)     │           │
│         └────────────────────┘  └──────────────────┘           │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ OBSERVABILITY LAYER                                             │
│  ┌──────────────┐      ┌──────────────┐                        │
│  │  Monitoring  │      │   Logging    │                        │
│  │  (Metrics)   │      │   (Logs)     │                        │
│  └──────────────┘      └──────────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## Day 1: Foundation - Linux Primitives

### Goals

- Set up isolated network namespaces
- Create virtual network interfaces
- Implement basic inter-namespace communication

### Tasks

#### Task 1.1: Create Network Namespaces (60 minutes)

Create six network namespaces representing your services:

```bash
# Create namespaces
sudo ip netns add nginx-lb
sudo ip netns add api-gateway
sudo ip netns add product-service
sudo ip netns add order-service
sudo ip netns add redis-cache
sudo ip netns add postgres-db
```

**Deliverable:** Screenshot showing all namespaces created

```bash
ip netns list
```

#### Task 1.2: Build a Virtual Bridge Network (90 minutes)

Create a bridge to connect all services:

```bash
# Create bridge
sudo ip link add br-app type bridge
sudo ip addr add 10.0.0.1/16 dev br-app
sudo ip link set br-app up
```

Connect each namespace to the bridge using veth pairs:

```bash
# Example for nginx-lb (repeat for all services)
sudo ip link add veth-nginx type veth peer name veth-nginx-br
sudo ip link set veth-nginx netns nginx-lb
sudo ip link set veth-nginx-br master br-app
sudo ip link set veth-nginx-br up

# Configure inside namespace
sudo ip netns exec nginx-lb ip addr add 10.0.0.10/16 dev veth-nginx
sudo ip netns exec nginx-lb ip link set veth-nginx up
sudo ip netns exec nginx-lb ip link set lo up
sudo ip netns exec nginx-lb ip route add default via 10.0.0.1
```






**Assignment:**

- nginx-lb: 10.0.0.10
- api-gateway: 10.0.0.20
- product-service: 10.0.0.30
- order-service: 10.0.0.40
- redis-cache: 10.0.0.50
- postgres-db: 10.0.0.60

**Deliverable:**

1. Network diagram showing your setup
2. Proof of connectivity (ping tests between all namespaces)

#### Task 1.3: Implement NAT for Internet Access (60 minutes)

Enable internet access for all namespaces:

```bash
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Add MASQUERADE rule
sudo iptables -t nat -A POSTROUTING -s 10.0.0.0/16 ! -o br-app -j MASQUERADE
```

**Deliverable:** Test internet connectivity from each namespace

```bash
sudo ip netns exec product-service ping -c 3 8.8.8.8
```

#### Task 1.4: Setup Port Forwarding (45 minutes)

Forward host port 8080 to nginx-lb:

```bash
sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 10.0.0.10:80
sudo iptables -A FORWARD -p tcp -d 10.0.0.10 --dport 80 -j ACCEPT
```

**Deliverable:** Document all iptables rules with explanations

---

## Day 2: Application Services

### Goals

- Deploy actual services in namespaces
- Implement service-to-service communication
- Test the complete application flow

### Tasks

#### Task 2.1: Deploy Nginx Load Balancer (90 minutes)

Create a simple nginx configuration that load balances to the API gateway:

```bash
# Create nginx config
sudo ip netns exec nginx-lb mkdir -p /tmp/nginx
```

Create `/tmp/nginx/nginx.conf`:

```nginx
events {
    worker_connections 1024;
}

http {
    upstream api_gateway {
        server 10.0.0.20:3000;
    }

    server {
        listen 80;
        
        location / {
            proxy_pass http://api_gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
        
        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
    }
}
```

Install and run nginx in the namespace:

```bash
# You may need to bind-mount necessary files
sudo ip netns exec nginx-lb nginx -c /tmp/nginx/nginx.conf
```

**Alternative:** Use Python's http.server as a simple proxy if nginx is complex.

**Deliverable:** Working load balancer responding to HTTP requests

#### Task 2.2: Create API Gateway (120 minutes)

Build a Node.js or Python API gateway that routes to backend services.

Create `api-gateway.py`:

```python
from flask import Flask, jsonify, request
import requests

app = Flask(__name__)

PRODUCT_SERVICE = "http://10.0.0.30:5000"
ORDER_SERVICE = "http://10.0.0.40:5000"

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "api-gateway"})

@app.route('/api/products', methods=['GET'])
def get_products():
    try:
        response = requests.get(f"{PRODUCT_SERVICE}/products")
        return jsonify(response.json()), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 503

@app.route('/api/products/<id>', methods=['GET'])
def get_product(id):
    try:
        response = requests.get(f"{PRODUCT_SERVICE}/products/{id}")
        return jsonify(response.json()), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 503

@app.route('/api/orders', methods=['POST'])
def create_order():
    try:
        response = requests.post(
            f"{ORDER_SERVICE}/orders",
            json=request.json
        )
        return jsonify(response.json()), response.status_code
    except Exception as e:
        return jsonify({"error": str(e)}), 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)
```

Run in namespace:

```bash
# Copy file to accessible location
# Install dependencies in namespace or use a Python virtual environment
sudo ip netns exec api-gateway python3 api-gateway.py &
```

**Deliverable:** API Gateway responding to requests and routing correctly

#### Task 2.3: Build Product Service (90 minutes)

Create `product-service.py`:

```python
from flask import Flask, jsonify
import redis
import json

app = Flask(__name__)

# Connect to Redis cache
try:
    cache = redis.Redis(host='10.0.0.50', port=6379, decode_responses=True)
except:
    cache = None

# Mock product database
PRODUCTS = {
    "1": {"id": "1", "name": "Laptop", "price": 999.99, "stock": 50},
    "2": {"id": "2", "name": "Mouse", "price": 29.99, "stock": 200},
    "3": {"id": "3", "name": "Keyboard", "price": 79.99, "stock": 150},
}

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "product-service"})

@app.route('/products', methods=['GET'])
def get_products():
    # Try cache first
    if cache:
        cached = cache.get('all_products')
        if cached:
            return jsonify(json.loads(cached))
    
    # Return products and cache
    products = list(PRODUCTS.values())
    if cache:
        cache.setex('all_products', 300, json.dumps(products))
    
    return jsonify(products)

@app.route('/products/<product_id>', methods=['GET'])
def get_product(product_id):
    # Try cache first
    if cache:
        cached = cache.get(f'product_{product_id}')
        if cached:
            return jsonify(json.loads(cached))
    
    product = PRODUCTS.get(product_id)
    if not product:
        return jsonify({"error": "Product not found"}), 404
    
    if cache:
        cache.setex(f'product_{product_id}', 300, json.dumps(product))
    
    return jsonify(product)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

**Deliverable:** Working product service with Redis caching

#### Task 2.4: Build Order Service (90 minutes)

Create `order-service.py`:

```python
from flask import Flask, jsonify, request
import psycopg2
from datetime import datetime
import json

app = Flask(__name__)

# Database connection
def get_db():
    return psycopg2.connect(
        host='10.0.0.60',
        database='orders',
        user='postgres',
        password='postgres'
    )

# Initialize database
def init_db():
    conn = get_db()
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE IF NOT EXISTS orders (
            id SERIAL PRIMARY KEY,
            customer_id VARCHAR(100),
            product_id VARCHAR(100),
            quantity INTEGER,
            total_price DECIMAL(10, 2),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    conn.commit()
    cur.close()
    conn.close()

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "order-service"})

@app.route('/orders', methods=['POST'])
def create_order():
    data = request.json
    
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute(
        '''INSERT INTO orders (customer_id, product_id, quantity, total_price)
           VALUES (%s, %s, %s, %s) RETURNING id''',
        (data['customer_id'], data['product_id'], 
         data['quantity'], data['total_price'])
    )
    
    order_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    
    return jsonify({"order_id": order_id, "status": "created"}), 201

@app.route('/orders/<order_id>', methods=['GET'])
def get_order(order_id):
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute('SELECT * FROM orders WHERE id = %s', (order_id,))
    order = cur.fetchone()
    
    cur.close()
    conn.close()
    
    if not order:
        return jsonify({"error": "Order not found"}), 404
    
    return jsonify({
        "id": order[0],
        "customer_id": order[1],
        "product_id": order[2],
        "quantity": order[3],
        "total_price": float(order[4]),
        "created_at": order[5].isoformat()
    })

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
```

**Deliverable:** Working order service with PostgreSQL integration

#### Task 2.5: Deploy Redis and PostgreSQL (60 minutes)

Run Redis:

```bash
sudo ip netns exec redis-cache redis-server --bind 0.0.0.0 &
```

Run PostgreSQL:

```bash
# This is complex in a namespace; alternatively use a simple Python-based
# in-memory store or SQLite, or use Docker for this part
sudo ip netns exec postgres-db postgres -D /var/lib/postgresql/data &
```

**Deliverable:** Both data stores operational and accessible

---

## Day 3: Monitoring and Debugging

### Goals

- Implement network monitoring
- Create debugging tools
- Add observability to your infrastructure

### Tasks

#### Task 3.1: Network Traffic Analysis (90 minutes)

Create a script that monitors traffic on the bridge:

```bash
#!/bin/bash
# monitor-traffic.sh

echo "=== Network Traffic Monitor ==="
echo "Monitoring bridge: br-app"
echo "Press Ctrl+C to stop"
echo ""

# Monitor traffic
sudo tcpdump -i br-app -n -v | while read line; do
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"
done
```

**Assignment:** Create a traffic analysis report showing:

- Packets between each service pair
- Protocol distribution (TCP/UDP/ICMP)
- Top talkers (most active services)

**Deliverable:** Traffic analysis report with graphs

#### Task 3.2: Service Health Monitoring (120 minutes)

Create `health-monitor.py`:

```python
#!/usr/bin/env python3
import requests
import time
from datetime import datetime
import json

SERVICES = {
    'nginx-lb': 'http://10.0.0.10/health',
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
    except Exception as e:
        return {"status": "DOWN", "error": str(e)}

def monitor():
    print("=== Service Health Monitor ===")
    print(f"Started at: {datetime.now()}")
    print("")
    
    while True:
        print(f"\n[{datetime.now().strftime('%H:%M:%S')}] Health Check:")
        print("-" * 60)
        
        for service, url in SERVICES.items():
            health = check_health(service, url)
            status_symbol = "✓" if health['status'] == 'UP' else "✗"
            
            if health['status'] == 'UP':
                print(f"{status_symbol} {service:20s} UP   (latency: {health['latency']*1000:.2f}ms)")
            else:
                print(f"{status_symbol} {service:20s} DOWN ({health.get('error', 'Unknown')})")
        
        time.sleep(10)

if __name__ == '__main__':
    monitor()
```

**Deliverable:** Health monitoring dashboard showing service status

#### Task 3.3: Connection Tracking Analysis (60 minutes)

Create a script to analyze active connections:

```bash
#!/bin/bash
# connection-tracker.sh

echo "=== Active Connection Tracker ==="
echo ""

while true; do
    clear
    echo "=== Active Connections ($(date)) ==="
    echo ""
    
    echo "Connections by Service:"
    echo "----------------------"
    
    # Track connections per namespace
    for ns in nginx-lb api-gateway product-service order-service; do
        count=$(sudo ip netns exec $ns ss -tan | grep ESTAB | wc -l)
        echo "$ns: $count active connections"
    done
    
    echo ""
    echo "Connection States:"
    echo "-----------------"
    sudo conntrack -L 2>/dev/null | grep "10.0.0" | \
        awk '{print $4}' | sort | uniq -c | sort -rn
    
    sleep 5
done
```

**Deliverable:** Connection tracking report

#### Task 3.4: Create Network Topology Visualizer (90 minutes)

Create a script that generates a visual representation of your network:

```python
#!/usr/bin/env python3
# topology-visualizer.py

import subprocess
import re

def get_bridge_info():
    """Get bridge and connected interfaces"""
    result = subprocess.run(
        ['bridge', 'link', 'show'],
        capture_output=True, text=True
    )
    return result.stdout

def get_namespace_ips():
    """Get IP addresses for all namespaces"""
    namespaces = ['nginx-lb', 'api-gateway', 'product-service', 
                  'order-service', 'redis-cache', 'postgres-db']
    
    ips = {}
    for ns in namespaces:
        result = subprocess.run(
            ['sudo', 'ip', 'netns', 'exec', ns, 'ip', 'addr'],
            capture_output=True, text=True
        )
        # Parse IP address
        match = re.search(r'inet (\d+\.\d+\.\d+\.\d+)', result.stdout)
        if match:
            ips[ns] = match.group(1)
    
    return ips

def draw_topology():
    """Draw ASCII network topology"""
    ips = get_namespace_ips()
    
    print("=" * 70)
    print(" " * 20 + "NETWORK TOPOLOGY")
    print("=" * 70)
    print()
    print("                    Internet")
    print("                        │")
    print("                        │ (NAT)")
    print("                        ↓")
    print("                ┌───────────────┐")
    print(f"                │  Host         │")
    print(f"                │  Port: 8080   │")
    print("                └───────┬───────┘")
    print("                        │ (DNAT)")
    print("                        ↓")
    print("            ┌───────────────────────┐")
    print(f"            │ Bridge: br-app        │")
    print(f"            │ IP: 10.0.0.1          │")
    print("            └─────┬─────────────────┘")
    print("                  │")
    print("      ┌───────────┼───────────┐")
    print("      │           │           │")
    
    for name, ip in ips.items():
        print(f"  {name:20s} {ip:15s}")
    
    print()
    print("=" * 70)

if __name__ == '__main__':
    draw_topology()
```

**Deliverable:** Network topology diagram

---

## Day 4: Advanced Networking

### Goals

- Implement service discovery
- Add load balancing
- Create network security policies

### Tasks

#### Task 4.1: Implement Simple Service Discovery (120 minutes)

Create a simple DNS-like service registry:

```python
#!/usr/bin/env python3
# service-registry.py

from flask import Flask, jsonify, request
import json
import time

app = Flask(__name__)

# Service registry
services = {}

@app.route('/register', methods=['POST'])
def register_service():
    """Register a service"""
    data = request.json
    service_name = data['name']
    service_ip = data['ip']
    service_port = data['port']
    
    services[service_name] = {
        'ip': service_ip,
        'port': service_port,
        'registered_at': time.time(),
        'health': 'unknown'
    }
    
    return jsonify({"status": "registered", "service": service_name})

@app.route('/discover/<service_name>', methods=['GET'])
def discover_service(service_name):
    """Discover a service"""
    if service_name in services:
        return jsonify(services[service_name])
    else:
        return jsonify({"error": "Service not found"}), 404

@app.route('/services', methods=['GET'])
def list_services():
    """List all services"""
    return jsonify(services)

@app.route('/deregister/<service_name>', methods=['DELETE'])
def deregister_service(service_name):
    """Deregister a service"""
    if service_name in services:
        del services[service_name]
        return jsonify({"status": "deregistered"})
    else:
        return jsonify({"error": "Service not found"}), 404

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8500)
```

Modify your services to register themselves on startup.

**Deliverable:** Working service discovery with all services registered

#### Task 4.2: Implement Round-Robin Load Balancing (120 minutes)

Modify the API Gateway to load balance between multiple instances:

```python
# Enhanced API Gateway with load balancing
import requests
import itertools

class LoadBalancer:
    def __init__(self, backends):
        self.backends = itertools.cycle(backends)
        self.backend_list = backends
    
    def get_backend(self):
        return next(self.backends)
    
    def health_check(self):
        healthy = []
        for backend in self.backend_list:
            try:
                response = requests.get(f"{backend}/health", timeout=1)
                if response.status_code == 200:
                    healthy.append(backend)
            except:
                pass
        self.backends = itertools.cycle(healthy)
        return healthy

# Use in routes
product_lb = LoadBalancer([
    "http://10.0.0.30:5000",
    "http://10.0.0.31:5000",  # Add second instance
    "http://10.0.0.32:5000",  # Add third instance
])
```

**Assignment:**

- Create multiple instances of product-service
- Implement load balancing
- Test distribution of requests

**Deliverable:** Load balancing working with request distribution logs

#### Task 4.3: Network Security Policies (90 minutes)

Implement iptables rules for security:

```bash
#!/bin/bash
# security-policies.sh

echo "Applying network security policies..."

# 1. Block direct access to database from outside app layer
sudo iptables -A FORWARD -s ! 10.0.0.40 -d 10.0.0.60 -p tcp --dport 5432 -j DROP
echo "✓ Database isolated to order-service only"

# 2. Block direct access to Redis from outside
sudo iptables -A FORWARD -s ! 10.0.0.30 -d 10.0.0.50 -p tcp --dport 6379 -j DROP
echo "✓ Redis isolated to product-service only"

# 3. Rate limit connections to API Gateway
sudo iptables -A FORWARD -d 10.0.0.20 -p tcp --dport 3000 \
    -m limit --limit 100/minute --limit-burst 20 -j ACCEPT
sudo iptables -A FORWARD -d 10.0.0.20 -p tcp --dport 3000 -j DROP
echo "✓ Rate limiting applied to API Gateway"

# 4. Allow only HTTP/HTTPS out from services
sudo iptables -A FORWARD -s 10.0.0.0/16 -p tcp --dport 80 -j ACCEPT
sudo iptables -A FORWARD -s 10.0.0.0/16 -p tcp --dport 443 -j ACCEPT
sudo iptables -A FORWARD -s 10.0.0.0/16 -p tcp --dport 53 -j ACCEPT
sudo iptables -A FORWARD -s 10.0.0.0/16 -p udp --dport 53 -j ACCEPT
echo "✓ Outbound traffic restricted"

# 5. Log dropped packets
sudo iptables -A FORWARD -j LOG --log-prefix "DROPPED: " --log-level 4

echo "Security policies applied successfully!"
```

**Deliverable:** Security policy document with rule explanations

#### Task 4.4: Implement Network Isolation (60 minutes)

Create separate networks for different tiers:

```bash
# Create frontend network
sudo ip link add br-frontend type bridge
sudo ip addr add 172.20.0.1/24 dev br-frontend
sudo ip link set br-frontend up

# Create backend network
sudo ip link add br-backend type bridge
sudo ip addr add 172.21.0.1/24 dev br-backend
sudo ip link set br-backend up

# Create database network
sudo ip link add br-database type bridge
sudo ip addr add 172.22.0.1/24 dev br-database
sudo ip link set br-database up
```

Move services to appropriate networks and configure routing.

**Deliverable:** Multi-network topology with documented routing rules

---

## Day 5: Docker Migration and Optimization

### Goals

- Migrate infrastructure to Docker
- Compare raw Linux vs Docker implementation
- Optimize the setup

### Tasks

#### Task 5.1: Containerize All Services (120 minutes)

Create Dockerfiles for each service:

```dockerfile
# Dockerfile.api-gateway
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api-gateway.py .

EXPOSE 3000

CMD ["python", "api-gateway.py"]
```

Create similar Dockerfiles for all services.

**Deliverable:** All services running in Docker containers

#### Task 5.2: Docker Compose Setup (90 minutes)

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  nginx-lb:
    image: nginx:alpine
    ports:
      - "8080:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf
    networks:
      - frontend
    depends_on:
      - api-gateway

  api-gateway:
    build:
      context: .
      dockerfile: Dockerfile.api-gateway
    networks:
      - frontend
      - backend
    depends_on:
      - product-service
      - order-service

  product-service:
    build:
      context: .
      dockerfile: Dockerfile.product-service
    networks:
      - backend
      - cache
    depends_on:
      - redis-cache
    deploy:
      replicas: 3

  order-service:
    build:
      context: .
      dockerfile: Dockerfile.order-service
    networks:
      - backend
      - database
    depends_on:
      - postgres-db

  redis-cache:
    image: redis:alpine
    networks:
      - cache

  postgres-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - database

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
  cache:
    driver: bridge
  database:
    driver: bridge

volumes:
  postgres-data:
```

**Deliverable:** Working Docker Compose setup

#### Task 5.3: Performance Comparison (90 minutes)

Benchmark your implementations:

```bash
#!/bin/bash
# benchmark.sh

echo "=== Performance Benchmark ==="

# Benchmark Linux namespace implementation
echo "Testing Linux namespace implementation..."
ab -n 10000 -c 100 http://localhost:8080/api/products > linux-benchmark.txt

# Benchmark Docker implementation
echo "Testing Docker implementation..."
ab -n 10000 -c 100 http://localhost:8080/api/products > docker-benchmark.txt

# Compare
echo ""
echo "Comparison:"
echo "-----------"
grep "Requests per second" linux-benchmark.txt docker-benchmark.txt
```

**Deliverable:** Performance comparison report

#### Task 5.4: Optimize Docker Setup (60 minutes)

Optimize your Docker images:

- Use multi-stage builds
- Minimize image sizes
- Implement health checks
- Add resource limits

**Deliverable:** Optimized Docker setup with documentation

---

## Day 6: Multi-Host Networking (Optional Advanced)

### Goals

- Implement overlay networking
- Connect containers across hosts
- Understand distributed networking

### Tasks

#### Task 6.1: Setup VXLAN Overlay (120 minutes)

If you have access to two hosts/VMs, create a VXLAN overlay:

```bash
# Host A
sudo ip link add vxlan100 type vxlan \
    id 100 \
    remote <HOST_B_IP> \
    dstport 4789 \
    dev eth0

sudo ip link set vxlan100 master br-app
sudo ip link set vxlan100 up
```

**Deliverable:** Working multi-host communication

#### Task 6.2: Docker Swarm Setup (90 minutes)

Initialize Docker Swarm and create overlay network:

```bash
# Initialize swarm
docker swarm init

# Create overlay network
docker network create --driver overlay --attachable app-overlay

# Deploy stack
docker stack deploy -c docker-compose.yml myapp
```

**Deliverable:** Services communicating across hosts

---

## Day 7: Documentation and Presentation

### Goals

- Complete comprehensive documentation
- Create presentation materials
- Prepare demonstration

### Tasks

#### Task 7.1: Technical Documentation (180 minutes)

Create complete documentation including:

1. **Architecture Document**
   - System overview
   - Component descriptions
   - Network topology
   - Data flow diagrams

2. **Implementation Guide**
   - Step-by-step setup instructions
   - Configuration files
   - Troubleshooting guide

3. **Operations Manual**
   - How to start/stop services
   - Monitoring procedures
   - Backup and recovery
   - Scaling guidelines

4. **Comparison Analysis**
   - Linux primitives vs Docker
   - Performance metrics
   - Pros and cons of each approach

#### Task 7.2: Create Presentation (120 minutes)

Prepare a 30-minute presentation covering:

- Problem statement
- Architecture decisions
- Implementation challenges
- Key learnings
- Performance results
- Future improvements

**Deliverable:** Slide deck and demo script

#### Task 7.3: Video Demonstration (60 minutes) (Optional)

Record a video demonstrating:

- System architecture walkthrough
- Live deployment
- Service interaction
- Monitoring and debugging
- Failure scenarios and recovery

**Deliverable:** 15-20 minute demo video

---

## Evaluation Criteria

Your project will be evaluated on:

### Technical Implementation (40%)

- [ ] All services deployed and functional
- [ ] Correct network configuration
- [ ] Proper isolation and security
- [ ] Working service-to-service communication
- [ ] NAT and port forwarding implemented
- [ ] Monitoring and logging in place

### Code Quality (20%)

- [ ] Clean, readable code
- [ ] Proper error handling
- [ ] Configuration management
- [ ] Security best practices
- [ ] Documentation in code

### Documentation (20%)

- [ ] Comprehensive architecture document
- [ ] Clear setup instructions
- [ ] Network diagrams
- [ ] Troubleshooting guide
- [ ] Performance analysis

### Presentation (20%)

- [ ] Clear explanation of concepts
- [ ] Demonstration of working system
- [ ] Discussion of challenges
- [ ] Comparison of approaches
- [ ] Professional delivery

---

## Bonus Challenges (Extra Credit)

### Bonus 1: Implement Service Mesh (Optional)

Add Envoy sidecar proxies to all services for:

- Traffic management
- Security (mTLS)
- Observability

### Bonus 2: Add Distributed Tracing

Implement OpenTelemetry or Jaeger for request tracing across services.

### Bonus 3: Chaos Engineering

Create scripts to simulate:

- Network failures
- Service crashes
- High latency
- Packet loss

Test your system's resilience.

### Bonus 4: Auto-Scaling

Implement automatic scaling based on:

- CPU usage
- Request rate
- Response time

### Bonus 5: CI/CD Pipeline

Create a complete pipeline:

- Automated testing
- Image building
- Deployment
- Rollback capability

---

## Resources and References

### Documentation

- Linux man pages: `man ip`, `man iptables`, `man netns`
- Docker documentation: <https://docs.docker.com>
- Python Flask: <https://flask.palletsprojects.com>
- PostgreSQL: <https://www.postgresql.org/docs>
- Redis: <https://redis.io/documentation>

### Tools

- tcpdump for packet capture
- wireshark for analysis
- ab (Apache Bench) for load testing
- curl for API testing
- jq for JSON processing

### Debugging Commands

```bash
# Network namespace debugging
sudo ip netns exec <namespace> ip addr
sudo ip netns exec <namespace> ip route
sudo ip netns exec <namespace> ss -tulpn

# Bridge inspection
bridge link show
bridge fdb show

# iptables
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v

# Connection tracking
sudo conntrack -L

# Docker networking
docker network inspect <network>
docker exec <container> ip addr
```

---

## Submission Requirements

Submit the following:

1. **Code Repository**
   - All source code
   - Configuration files
   - Scripts
   - README with setup instructions

2. **Documentation**
   - Architecture document (PDF)
   - Implementation guide (Markdown)
   - Operations manual (PDF)
   - Comparison analysis (PDF)

3. **Presentation Materials**
   - Slide deck (PDF/PPT)
   - Demo video (MP4)
   - Screenshots and diagrams

4. **Test Results**
   - Performance benchmarks
   - Test logs
   - Traffic analysis

---

## Tips for Success

1. **Start Early**: Don't wait until day 7 to start documentation
2. **Document As You Go**: Take notes and screenshots during implementation
3. **Test Incrementally**: Test each component before moving to the next
4. **Use Version Control**: Commit frequently with meaningful messages
5. **Ask Questions**: Don't struggle alone - reach out for help
6. **Be Creative**: Add your own improvements and ideas
7. **Focus on Understanding**: Don't just copy-paste - understand each command
8. **Backup Regularly**: Keep multiple backups of your work

---

## Common Issues and Solutions

### Issue: Cannot create namespace

**Solution:** Check if you have root privileges

### Issue: veth pair not communicating

**Solution:** Ensure both ends are UP and IP addresses are configured

### Issue: No internet access from namespace

**Solution:** Check IP forwarding and iptables MASQUERADE rule

### Issue: Services cannot resolve each other

**Solution:** Implement service discovery or use IP addresses directly

### Issue: Port already in use

**Solution:** Check for conflicting services and change ports if needed

---

## Final Notes

This project is designed to give you deep, practical experience with container networking. By the end, you will understand not just how to use containers, but how they actually work under the hood.

Remember: The goal is not perfection, but learning. Document your failures and challenges - they're often more valuable than successes.

Good luck, and enjoy building!

---

## Project Timeline

```
Day 1: Foundation
├── Morning:   Network namespaces and bridge setup
├── Afternoon: NAT and port forwarding
└── Evening:   Testing and documentation

Day 2: Application Services  
├── Morning:   Nginx and API Gateway
├── Afternoon: Product and Order services
└── Evening:   Redis and PostgreSQL integration

Day 3: Monitoring
├── Morning:   Traffic analysis
├── Afternoon: Health monitoring
└── Evening:   Visualization tools

Day 4: Advanced Features
├── Morning:   Service discovery
├── Afternoon: Load balancing
└── Evening:   Security policies

Day 5: Docker Migration
├── Morning:   Containerization
├── Afternoon: Docker Compose
└── Evening:   Performance testing

Day 6: Multi-Host (Optional)
├── Morning:   VXLAN setup
├── Afternoon: Docker Swarm
└── Evening:   Testing

Day 7: Documentation
├── Morning:   Technical documentation
├── Afternoon: Presentation preparation
└── Evening:   Final review and submission
```

**Estimated Total Time:** 40-60 hours over 7 days

---

## Questions to Answer in Your Documentation

1. What are the advantages of using network namespaces?
2. How does NAT enable container internet access?
3. What is the role of iptables in container networking?
4. How do veth pairs work at the kernel level?
5. What are the differences between bridge and overlay networks?
6. How does service discovery improve microservices architecture?
7. What security considerations are important in container networking?
8. How does Docker's networking compare to raw Linux primitives?
9. What are the performance implications of different networking approaches?
10. How would you scale this system to handle 10x more traffic?

---

**Remember:** This is a learning journey. Take your time, experiment, break things, fix them, and most importantly - have fun!
