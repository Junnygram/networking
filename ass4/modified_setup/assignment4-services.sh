#!/bin/bash

# ===================================================================================
# Assignment 4 (Part B) - Load Balanced Services Script (v3 - Self-Contained)
#
# This script starts, stops, and monitors the application stack for the segmented network.
# It is self-contained and includes its own status and health check commands
# tailored for the new network architecture.
#
# It assumes:
#   1. The network from `assignment4-network.sh` is already running.
# ===================================================================================

# Exit on any error
set -e

# --- Global variables for venv and command paths ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VENV_DIR="$SCRIPT_DIR/../../networking_venv" # Assumes venv is in the root project directory
PYTHON_CMD="$VENV_DIR/bin/python"

# --- Prerequisites: Ensure Python venv and packages are ready ---
ensure_python_venv() {
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating Python virtual environment at $VENV_DIR..."
        python3 -m venv "$VENV_DIR"
        "$PYTHON_CMD" -m pip install -U pip
    fi
    echo "--- Ensuring Python packages are installed in venv ---"
    "$PYTHON_CMD" -m pip install -q -U Flask requests psycopg2-binary redis
    echo "✅ Python virtual environment ready."
}

# --- Create all application files ---
create_files() {
    if [ -f "$SCRIPT_DIR/api-gateway-lb.py" ]; then return; fi
    echo "--- Creating application source files for load-balanced setup ---"

    # Nginx config - pointing to the new frontend IP for the gateway
    cat <<'EOF' > "$SCRIPT_DIR/nginx.conf"
events { worker_connections 1024; }
http {
    upstream api_gateway { server 172.20.0.20:3000; }
    server {
        listen 80;
        location / {
            proxy_pass http://api_gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    # API Gateway with Load Balancing
    cat <<'EOF' > "$SCRIPT_DIR/api-gateway-lb.py"
from flask import Flask, jsonify, request
import requests, os, itertools, sys

app = Flask(__name__)

class RoundRobinLoadBalancer:
    def __init__(self, backends):
        self.iterator = itertools.cycle(backends)
    def get_next_backend(self):
        return next(self.iterator)

PRODUCT_BACKENDS = os.getenv("PRODUCT_SERVICE_URLS", "http://172.21.0.30:5000,http://172.21.0.31:5000,http://172.21.0.32:5000").split(',')
ORDER_SERVICE = os.getenv("ORDER_SERVICE_URL", "http://172.21.0.40:5000")

product_lb = RoundRobinLoadBalancer(PRODUCT_BACKENDS)

@app.route('/health')
def health(): return jsonify({"status": "healthy"})

@app.route('/api/products', methods=['GET'])
def get_products():
    backend = product_lb.get_next_backend()
    print(f"Forwarding to product-service at {backend}", file=sys.stderr)
    try:
        res = requests.get(f"{backend}/products", timeout=2)
        res.raise_for_status()
        return jsonify(res.json()), res.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Service at {backend} unavailable", "details": str(e)}), 503

@app.route('/api/orders', methods=['POST'])
def create_order():
    try:
        res = requests.post(f"{ORDER_SERVICE}/orders", json=request.json, timeout=2)
        res.raise_for_status()
        return jsonify(res.json()), res.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Order service unavailable", "details": str(e)}), 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False)
EOF

    # Product service with wait logic
    cat <<'EOF' > "$SCRIPT_DIR/product-service.py"
from flask import Flask, jsonify
import redis, os, time, sys

app = Flask(__name__)
REDIS_HOST = os.getenv("REDIS_HOST", "172.22.0.50")
cache = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True, socket_connect_timeout=2)
PRODUCTS = {"1": {"id": "1", "name": "Laptop"}, "2": {"id": "2", "name": "Mouse"}}

def wait_for_redis():
    retries = 15
    while retries > 0:
        try:
            cache.ping()
            return True
        except redis.exceptions.ConnectionError:
            print(f"Waiting for Redis... ({retries} retries left)", file=sys.stderr)
            retries -= 1
            time.sleep(2)
    return False

@app.route('/products', methods=['GET'])
def get_products():
    instance_ip = os.popen('ip addr show eth0').read().split("inet ")[1].split("/")[0]
    return jsonify({"products": list(PRODUCTS.values()), "served_by": instance_ip})

if __name__ == '__main__':
    if wait_for_redis():
        app.run(host='0.0.0.0', port=5000, debug=False)
    else:
        print("❌ Could not connect to Redis. Exiting.", file=sys.stderr)
        sys.exit(1)
EOF

    # Order service with wait logic
    cat <<'EOF' > "$SCRIPT_DIR/order-service.py"
from flask import Flask, jsonify, request
import psycopg2, os, sys, time, json

app = Flask(__name__)
# The host postgres server is accessible via its IP on the backend bridge
DB_HOST = os.getenv("DB_HOST", "172.21.0.1") 

def get_db():
    return psycopg2.connect(host=DB_HOST, dbname="orders", user="postgres", password="postgres", connect_timeout=3)

def wait_for_db():
    retries = 15
    while retries > 0:
        try:
            conn = get_db()
            conn.close()
            return True
        except psycopg2.OperationalError:
            print(f"Waiting for DB... ({retries} retries left)", file=sys.stderr)
            retries -= 1
            time.sleep(2)
    return False

@app.route('/orders', methods=['POST'])
def create_order():
    conn = get_db()
    cur = conn.cursor()
    cur.execute('INSERT INTO orders (data) VALUES (%s) RETURNING id', (json.dumps(request.json),))
    order_id = cur.fetchone()[0]
    conn.commit()
    return jsonify({"order_id": order_id}), 201

if __name__ == '__main__':
    if wait_for_db():
        app.run(host='0.0.0.0', port=5000, debug=False)
    else:
        print("❌ Could not connect to DB. Exiting.", file=sys.stderr)
        sys.exit(1)
EOF
    echo "✅ Application files created."
}

# --- Function to stop service processes ---
stop_procs() {
    echo "--- Stopping all service processes ---"
    sudo pkill -9 -f "nginx" || true
    sudo pkill -9 -f "api-gateway-lb.py" || true
    sudo pkill -9 -f "product-service.py" || true
    sudo pkill -9 -f "order-service.py" || true
    sudo pkill -9 -f "redis-server 0.0.0.0:6379" || true
    echo "✅ Processes stopped."
}

# --- Function to start all services (Idempotent) ---
start_services() {
    ensure_python_venv
    create_files
    stop_procs
    
    echo "--- Starting all services on segmented network ---"
    echo "Starting Redis and Nginx..."
    sudo ip netns exec redis-cache redis-server --bind 0.0.0.0 --port 6379 --daemonize yes --protected-mode no
    sudo mkdir -p /tmp/nginx && sudo cp "$SCRIPT_DIR/nginx.conf" /tmp/nginx/nginx.conf
    sudo ip netns exec nginx-lb nginx -c /tmp/nginx/nginx.conf
    sleep 3

    echo "Starting application services..."
    sudo ip netns exec api-gateway "$PYTHON_CMD" "$SCRIPT_DIR/api-gateway-lb.py" > /tmp/api-gateway-lb.log 2>&1 &
    sudo ip netns exec order-service "$PYTHON_CMD" "$SCRIPT_DIR/order-service.py" > /tmp/order-service.log 2>&1 &
    
    echo "Starting Product Service replicas..."
    sudo ip netns exec product-service-1 "$PYTHON_CMD" "$SCRIPT_DIR/product-service.py" > /tmp/product-service-1.log 2>&1 &
    sudo ip netns exec product-service-2 "$PYTHON_CMD" "$SCRIPT_DIR/product-service.py" > /tmp/product-service-2.log 2>&1 &
    sudo ip netns exec product-service-3 "$PYTHON_CMD" "$SCRIPT_DIR/product-service.py" > /tmp/product-service-3.log 2>&1 &

    echo ""
    echo "✅ All services started."
}

# --- NEW: Function to check service status ---
status_services() {
    echo "--- Checking service status ---"
    echo; echo "=> Nginx Processes:"; sudo pgrep -af "[n]ginx" || echo "  Not running."
    echo; echo "=> API Gateway LB Processes:"; sudo pgrep -af "[a]pi-gateway-lb.py" || echo "  Not running."
    echo; echo "=> Product Service Replica 1:"; sudo ip netns exec product-service-1 pgrep -af "[p]roduct-service.py" || echo "  Not running."
    echo; echo "=> Product Service Replica 2:"; sudo ip netns exec product-service-2 pgrep -af "[p]roduct-service.py" || echo "  Not running."
    echo; echo "=> Product Service Replica 3:"; sudo ip netns exec product-service-3 pgrep -af "[p]roduct-service.py" || echo "  Not running."
    echo; echo "=> Order Service Processes:"; sudo ip netns exec order-service pgrep -af "[o]rder-service.py" || echo "  Not running."
    echo; echo "=> Redis Processes:"; sudo pgrep -af "[r]edis-server" || echo "  Not running."
    echo
}

# --- NEW: Function to run health checks ---
health_check() {
    echo "--- Running health checks for segmented network ---"
    # The health check needs python `requests` which is in our venv
    ensure_python_venv

    HEALTH_CHECK_SCRIPT="$SCRIPT_DIR/health-check.py"

    cat <<EOF > "$HEALTH_CHECK_SCRIPT"
import requests, time, sys

# These are the IPs for the NEW segmented network
SERVICES = {
    'nginx-lb': 'http://172.20.0.10:80',
    'api-gateway-lb': 'http://172.20.0.20:3000/health',
    'product-service-1': 'http://172.21.0.30:5000/products', # product service doesn't have /health
    'product-service-2': 'http://172.21.0.31:5000/products',
    'product-service-3': 'http://172.21.0.32:5000/products',
    'order-service': 'http://172.21.0.40:5000/orders', # order service also doesn't have /health
}

all_ok = True
print("-" * 60)
for service, url in SERVICES.items():
    try:
        # Use a POST for /orders to avoid a "Method not allowed"
        if 'orders' in url:
            res = requests.post(url, timeout=2, json={})
        else:
            res = requests.get(url, timeout=2)
        
        # A 400 Bad Request on /orders is OK, it means the service is up.
        if res.status_code in [200, 400]:
            print(f"✅ {service:20s} UP   (latency: {res.elapsed.total_seconds()*1000:.2f}ms)")
        else:
            all_ok = False
            print(f"❌ {service:20s} DOWN | HTTP Status: {res.status_code}")
    except requests.exceptions.RequestException:
        all_ok = False
        print(f"❌ {service:20s} DOWN | Reason: Connection refused or timed out")
print("-" * 60)
if not all_ok:
    sys.exit(1)
EOF
    
    # Run health check from the correct venv
    "$PYTHON_CMD" "$HEALTH_CHECK_SCRIPT"
    rm -f "$HEALTH_CHECK_SCRIPT"
}


# --- Function to clean up generated files ---
clean_files() {
    echo "--- Deleting all generated files and logs ---"
    sudo rm -rf /tmp/nginx
    rm -f "$SCRIPT_DIR/nginx.conf"
    rm -f "$SCRIPT_DIR/api-gateway-lb.py"
    rm -f "$SCRIPT_DIR/product-service.py"
    rm -f "$SCRIPT_DIR/order-service.py"
    rm -f "$SCRIPT_DIR/health-check.py"
    rm -f /tmp/*.log 2>/dev/null || true
    echo "✅ File cleanup complete."
}

# --- Main script logic ---
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_procs
        clean_files
        ;;
    restart)
        start_services # Start is now idempotent
        ;;
    status)
        status_services
        ;;
    health)
        health_check
        ;;
    clean)
        stop_procs
        clean_files
        ;;
    *)
        echo "Usage: sudo $0 {start|stop|restart|status|health|clean}"
        exit 1
        ;;
esac

exit 0
