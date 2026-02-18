# Building a Container Network

> Step-by-step guide to creating a full multi-service container network from scratch using [[Linux]] primitives — no [[Docker]] required.
>
> Part of [[Container Networking]] · Builds on [[Linux Network Primitives]]

---

## The Network Layout

A microservices e-commerce platform with 6 services, each in its own [[Network Namespace]]:

| Namespace | Short Name | IP Address | Role |
|-----------|-----------|------------|------|
| `nginx-lb` | `lb` | `10.0.0.10/24` | Load balancer / reverse proxy |
| `api-gateway` | `api` | `10.0.0.20/24` | Central API router |
| `product-service` | `prod` | `10.0.0.30/24` | Product data ([[Flask]]) |
| `order-service` | `ord` | `10.0.0.40/24` | Order management ([[Flask]]) |
| `redis-cache` | `cache` | `10.0.0.50/24` | Caching layer |
| `postgres-db` | `pg` | `10.0.0.60/24` | Persistent storage |

> [!note] Interface name limit
> [[Linux]] limits network interface names to **15 characters**. Use short names like `veth-lb` instead of `veth-nginx-loadbalancer`, or commands fail silently.

---

## Step 1: Create the Network

This script is **idempotent** — run it multiple times safely. It cleans up first, then rebuilds everything.

```bash
#!/bin/bash
set -e

NAMESPACES=("api-gateway" "postgres-db" "nginx-lb" "order-service" "product-service" "redis-cache")
SHORT_NAMES=("api" "pg" "lb" "ord" "prod" "cache")
IPS=("10.0.0.20/24" "10.0.0.60/24" "10.0.0.10/24" "10.0.0.40/24" "10.0.0.30/24" "10.0.0.50/24")

BRIDGE_NAME="br0"
BRIDGE_IP="10.0.0.1/24"
BRIDGE_SUBNET="10.0.0.0/24"
DEFAULT_IFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}')

# --- Cleanup (safe to run even if nothing exists) ---
cleanup() {
    echo "--- Cleaning up ---"
    sudo iptables -t nat -D POSTROUTING -s "$BRIDGE_SUBNET" -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null || true
    for ns in "${NAMESPACES[@]}"; do
        sudo ip netns delete "$ns" 2>/dev/null || true
    done
    sudo ip link delete "$BRIDGE_NAME" type bridge 2>/dev/null || true
}

# --- Build the network ---
setup() {
    echo "--- Building network ---"

    # Enable IP forwarding
    sudo sysctl -w net.ipv4.ip_forward=1

    # NAT for internet access
    sudo iptables -t nat -A POSTROUTING -s "$BRIDGE_SUBNET" -o "$DEFAULT_IFACE" -j MASQUERADE

    # Create the bridge
    sudo ip link add "$BRIDGE_NAME" type bridge
    sudo ip addr add "$BRIDGE_IP" dev "$BRIDGE_NAME"
    sudo ip link set "$BRIDGE_NAME" up

    # Allow forwarding through the bridge
    sudo iptables -A FORWARD -i "$BRIDGE_NAME" -j ACCEPT
    sudo iptables -A FORWARD -o "$BRIDGE_NAME" -j ACCEPT

    # Create each namespace and connect it
    for i in "${!NAMESPACES[@]}"; do
        NS=${NAMESPACES[$i]}
        SHORT=${SHORT_NAMES[$i]}
        IP=${IPS[$i]}
        VETH_NS="veth-$SHORT"
        VETH_BR="${VETH_NS}-br"

        echo "Setting up: $NS ($IP)"

        # Create namespace
        sudo ip netns add "$NS"

        # Create veth pair
        sudo ip link add "$VETH_NS" type veth peer name "$VETH_BR"

        # Connect one end to bridge, other to namespace
        sudo ip link set "$VETH_BR" master "$BRIDGE_NAME"
        sudo ip link set "$VETH_NS" netns "$NS"

        # Configure inside namespace
        sudo ip netns exec "$NS" ip addr add "$IP" dev "$VETH_NS"
        sudo ip netns exec "$NS" ip link set dev "$VETH_NS" up
        sudo ip netns exec "$NS" ip link set dev lo up
        sudo ip netns exec "$NS" ip route add default via "$(echo "$BRIDGE_IP" | cut -d'/' -f1)"

        # Bring up bridge side
        sudo ip link set dev "$VETH_BR" up
    done
}

cleanup
setup

# Verify internet from each namespace
echo ""
echo "--- Verifying connectivity ---"
for ns in "${NAMESPACES[@]}"; do
    echo "--> $ns:"
    if sudo ip netns exec "$ns" bash -c "echo 'nameserver 8.8.8.8' > /etc/resolv.conf && ping -c 2 -W 5 google.com" &>/dev/null; then
        echo "    ✅ Internet access works"
    else
        echo "    ❌ Failed"
    fi
done
```

### Verify the network

```bash
# Inter-namespace connectivity
sudo ip netns exec nginx-lb ping -c 2 10.0.0.20     # → api-gateway ✅
sudo ip netns exec product-service ping -c 2 10.0.0.60  # → postgres ✅

# Internet from any namespace
sudo ip netns exec redis-cache ping -c 2 8.8.8.8    # ✅

# View bridge and attached interfaces
bridge link show
ip addr show br0
```

---

## Step 2: Deploy Services

With the network running, deploy actual applications into each namespace.

| Service | Technology | How it runs |
|---------|-----------|-------------|
| [[Nginx]] | Reverse proxy | Listens in `nginx-lb`, routes to api-gateway |
| API Gateway | [[Flask]] | Central router in `api-gateway` |
| Product Service | [[Flask]] | REST API in `product-service` |
| Order Service | [[Flask]] | REST API in `order-service` |
| [[Redis]] | Cache | Listens in `redis-cache` |
| [[PostgreSQL]] | Database | Listens in `postgres-db` |

### Running services inside namespaces

```bash
# Redis
sudo ip netns exec redis-cache redis-server --bind 10.0.0.50 --port 6379 &

# PostgreSQL
sudo ip netns exec postgres-db su - postgres -c "pg_ctlcluster 14 main start"

# Flask apps (using a virtual environment)
sudo ip netns exec product-service /path/to/venv/bin/python product_app.py &

# Nginx (with config pointing to api-gateway IP)
sudo ip netns exec nginx-lb nginx -c /path/to/nginx.conf
```

### Lifecycle management

Wrap everything in a script with lifecycle commands:

```bash
./services.sh start     # Start all services in dependency order
./services.sh stop      # Kill all service processes
./services.sh restart   # Stop then start
./services.sh status    # Show what's running per namespace
```

**Critical startup patterns:**
- Start dependencies first: [[PostgreSQL]] → [[Redis]] → backends → [[Nginx]]
- Use `wait_for_db()` retry loops in application code
- Redirect output to logs: `command > /tmp/service.log 2>&1 &`
- Use Python virtual environments for [[Flask]] apps

```python
# Application-level retry loop
import time, psycopg2

def wait_for_db(host, max_retries=30, delay=2):
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(host=host, database="orders",
                                     user="appuser", password="secret")
            conn.close()
            print("Database ready!")
            return
        except psycopg2.OperationalError:
            print(f"Waiting for database... ({attempt + 1}/{max_retries})")
            time.sleep(delay)
    raise Exception("Database not available")
```

---

## Step 3: Monitor and Debug

See [[Linux Network Primitives]] for understanding what these tools inspect.

### Traffic analysis with [[tcpdump]]

```bash
# All traffic on the bridge
sudo tcpdump -i br0 -c 20

# Only HTTP traffic
sudo tcpdump -i br0 port 80 -A

# Traffic in a specific namespace
sudo ip netns exec api-gateway tcpdump -i veth-api -c 10
```

### Health checking

```bash
# Single service check
sudo ip netns exec nginx-lb curl -s -o /dev/null -w "%{http_code}" http://10.0.0.20:3000/health

# Continuous monitor
while true; do
    for svc in "nginx-lb:10.0.0.10:80" "api-gateway:10.0.0.20:3000"; do
        NS=$(echo $svc | cut -d: -f1)
        IP=$(echo $svc | cut -d: -f2)
        PORT=$(echo $svc | cut -d: -f3)
        STATUS=$(sudo ip netns exec $NS curl -s -o /dev/null -w "%{http_code}" \
                 http://$IP:$PORT/health 2>/dev/null || echo "DOWN")
        echo "$NS: $STATUS"
    done
    sleep 5
done
```

### Connection tracking and topology

```bash
# Active connections through the kernel
sudo conntrack -L

# Count connections per IP
sudo conntrack -L 2>/dev/null | grep 10.0.0.20 | wc -l

# Namespace topology overview
for ns in $(ip netns list); do
    echo "=== $ns ==="
    sudo ip netns exec $ns ip -4 addr show | grep inet
done

# Full debugging toolkit
sudo ip netns exec <ns> ip addr show          # Interfaces
sudo ip netns exec <ns> nslookup google.com   # DNS
sudo ip netns exec <ns> ping -c 3 <target>    # Connectivity
sudo ip netns exec <ns> nc -zv <ip> <port>    # Port check
sudo ip netns exec <ns> ss -tlnp             # Listening ports
bridge link show                              # Bridge connections
bridge fdb show                               # Forwarding database
```

---

## Step 4: Network Segmentation

### The problem with a flat network

When all services share one bridge, a compromised container can reach everything — including the database. This is dangerous.

### Solution: multiple bridges

Separate services into distinct network zones:

```
┌─────────────────────────────────────────┐
│              br-frontend                │
│         (172.20.0.0/24)                 │
│    ┌─────────┐    ┌──────────┐          │
│    │  Nginx  │    │ API GW   │          │
│    │  (LB)   │    │ (router) │          │
│    └─────────┘    └──┬───────┘          │
└──────────────────────┼──────────────────┘
                       │ multi-homed
┌──────────────────────┼──────────────────┐
│              br-backend                 │
│         (172.21.0.0/24)                 │
│    ┌──────────┐  ┌──────────┐           │
│    │ Product  │  │  Order   │           │
│    │ Service  │  │ Service  │           │
│    └──────────┘  └──────────┘           │
└─────────────────────────────────────────┘
                       │
┌──────────────────────┼──────────────────┐
│              br-database                │
│         (172.22.0.0/24)                 │
│    ┌──────────┐  ┌──────────┐           │
│    │  Redis   │  │ Postgres │           │
│    └──────────┘  └──────────┘           │
└─────────────────────────────────────────┘
```

**Why segment:**
- Database is **unreachable** from frontend — [[defense in depth]]
- API Gateway is **multi-homed** (interfaces on frontend + backend)
- Mirrors real cloud [[VPC]] architecture

```bash
# Create three bridges
sudo ip link add br-frontend type bridge
sudo ip addr add 172.20.0.1/24 dev br-frontend && sudo ip link set br-frontend up

sudo ip link add br-backend type bridge
sudo ip addr add 172.21.0.1/24 dev br-backend && sudo ip link set br-backend up

sudo ip link add br-database type bridge
sudo ip addr add 172.22.0.1/24 dev br-database && sudo ip link set br-database up
```

### Security policies with [[iptables]]

```bash
# Default: deny all forwarding
sudo iptables -P FORWARD DROP

# Allow established connections (critical!)
sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Only allow: frontend → backend, backend → database
sudo iptables -A FORWARD -i br-frontend -o br-backend -j ACCEPT
sudo iptables -A FORWARD -i br-backend -o br-database -j ACCEPT

# Everything else: denied by default
```

### Load balancing

Run multiple replicas and distribute traffic with round-robin:

```python
backends = ["172.21.0.30:5000", "172.21.0.31:5000", "172.21.0.32:5000"]
current = 0

def get_backend():
    global current
    backend = backends[current]
    current = (current + 1) % len(backends)
    return backend
```

### Service discovery

Instead of hardcoding IPs, build a simple registry:

```python
from flask import Flask, request

app = Flask(__name__)
registry = {}

@app.route('/register', methods=['POST'])
def register():
    data = request.json
    registry[data['name']] = {'ip': data['ip'], 'port': data['port']}
    return {'status': 'registered'}

@app.route('/discover/<name>')
def discover(name):
    return registry.get(name, {'error': 'not found'})
```

---

## Next Steps

Everything built here manually is exactly what [[Docker and Docker Compose]] automates. Continue there to see how the same architecture is expressed declaratively.

---

#container-networking #linux #hands-on #networking #iptables #namespaces
