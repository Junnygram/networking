#!/bin/bash

# ===================================================================================
# Assignment 4 (Part B) - Load Balanced Services Script
#
# This script starts and stops the application stack for the segmented network,
# including multiple replicas of the product-service and a load-balancing API gateway.
#
# It assumes:
#   1. The network from `assignment4-network.sh` is already running.
#   2. All prerequisite software is installed.
#
# Usage:
#   sudo ./assignment4-services.sh start   # Creates files and starts all services
#   sudo ./assignment4-services.sh stop    # Stops all services and deletes files
#
# ===================================================================================

set -e

# --- Application file content and creation ---
create_files() {
    echo "--- Creating application source files for load-balanced setup ---"

    # Nginx config (no changes needed)
    cat <<'EOF' > nginx.conf
events { worker_connections 1024; }
http {
    upstream api_gateway { server 172.20.0.20:3000; }
    server {
        listen 80;
        server_name localhost;
        location / {
            proxy_pass http://api_gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
        }
    }
}
EOF

    # NEW: API Gateway with Load Balancing
    cat <<'EOF' > api-gateway-lb.py
from flask import Flask, jsonify, request
import requests
import os
import itertools

app = Flask(__name__)

# --- Load Balancer Implementation ---
class RoundRobinLoadBalancer:
    def __init__(self, backends):
        self.backends = backends
        self.iterator = itertools.cycle(self.backends)
    
    def get_next_backend(self):
        return next(self.iterator)

# Define the backend services. In a real system, this would come from the service registry.
PRODUCT_SERVICE_BACKENDS = os.getenv("PRODUCT_SERVICE_URLS", "http://172.21.0.30:5000,http://172.21.0.31:5000,http://172.21.0.32:5000").split(',')
ORDER_SERVICE = os.getenv("ORDER_SERVICE_URL", "http://172.21.0.40:5000")

product_lb = RoundRobinLoadBalancer(PRODUCT_SERVICE_BACKENDS)

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "api-gateway-lb"})

@app.route('/api/products', methods=['GET'])
def get_products():
    backend = product_lb.get_next_backend()
    print(f"Forwarding to product-service at {backend}")
    try:
        response = requests.get(f"{backend}/products")
        response.raise_for_status()
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Product service at {backend} is unavailable", "details": str(e)}), 503

# Other routes remain the same...
@app.route('/api/orders', methods=['POST'])
def create_order():
    try:
        response = requests.post(f"{ORDER_SERVICE}/orders", json=request.json)
        response.raise_for_status()
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Order service is unavailable", "details": str(e)}), 503

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)
EOF

    # Product service (no changes needed)
    cat <<'EOF' > product-service.py
from flask import Flask, jsonify
import redis, json, os

app = Flask(__name__)
REDIS_HOST = os.getenv("REDIS_HOST", "172.22.0.50")
cache = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)
PRODUCTS = {"1": {"id": "1", "name": "Laptop", "price": 999.99}, "2": {"id": "2", "name": "Mouse", "price": 29.99}}

@app.route('/products', methods=['GET'])
def get_products():
    # Adding which instance is responding for demonstration
    instance_ip = os.popen('ip addr show eth0').read().split("inet ")[1].split("/")[0]
    products = list(PRODUCTS.values())
    return jsonify({"products": products, "served_by": instance_ip})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

    # Order service (no changes needed, but will update IP)
    cat <<'EOF' > order-service.py
from flask import Flask, jsonify, request
import psycopg2, os, sys

app = Flask(__name__)
DB_HOST = os.getenv("DB_HOST", "172.22.0.60")
DB_NAME = os.getenv("DB_NAME", "orders")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")
def get_db(): return psycopg2.connect(host=DB_HOST, database=DB_NAME, user=DB_USER, password=DB_PASSWORD)

def init_db():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('CREATE TABLE IF NOT EXISTS orders (id SERIAL PRIMARY KEY, data JSONB)')
        conn.commit()
    except psycopg2.OperationalError as e:
        print(f"DB connection failed: {e}", file=sys.stderr)
        sys.exit(1)

@app.route('/orders', methods=['POST'])
def create_order():
    conn = get_db()
    cur = conn.cursor()
    cur.execute('INSERT INTO orders (data) VALUES (%s) RETURNING id', (json.dumps(request.json),))
    order_id = cur.fetchone()[0]
    conn.commit()
    return jsonify({"order_id": order_id}), 201

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
EOF
    echo "✅ Application files created."
}

# --- Function to delete all application files ---
delete_files() {
    echo "--- Deleting application source files ---"
    rm -f nginx.conf api-gateway-lb.py product-service.py order-service.py
    echo "✅ Application files deleted."
}

# --- Function to start all services ---
start_services() {
    create_files
    
    echo ""
    echo "--- Starting all services on segmented network ---"

    echo "Starting Redis and Nginx..."
    sudo ip netns exec redis-cache redis-server --bind 0.0.0.0 --port 6379 --daemonize yes
    sudo mkdir -p /tmp/nginx && sudo cp nginx.conf /tmp/nginx/nginx.conf
    sudo ip netns exec nginx-lb nginx -c /tmp/nginx/nginx.conf
    sleep 1

    echo "Starting application services..."
    sudo ip netns exec api-gateway python3 api-gateway-lb.py &
    sudo ip netns exec order-service python3 order-service.py &
    
    echo "Starting Product Service replicas for load balancing..."
    sudo ip netns exec product-service-1 python3 product-service.py &
    sudo ip netns exec product-service-2 python3 product-service.py &
    sudo ip netns exec product-service-3 python3 product-service.py &

    echo ""
    echo "✅ All services started."
    echo "To test load balancing, run multiple times: curl http://127.0.0.1:8080/api/products"
    echo "(Requires 'sudo iptables -t nat -A PREROUTING -p tcp --dport 8080 -j DNAT --to-destination 172.20.0.10:80')"
}

# --- Function to stop all services ---
stop_services() {
    echo "--- Stopping all services ---"

    pkill -f "nginx: master process" || true
    pkill -f "api-gateway-lb.py" || true
    pkill -f "product-service.py" || true
    pkill -f "order-service.py" || true
    sudo ip netns exec redis-cache redis-cli shutdown 2>/dev/null || pkill -f "redis-server" || true
    
    sudo rm -rf /tmp/nginx
    delete_files
    
    echo "✅ All services stopped and files cleaned up."
}

# --- Main script logic ---
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    *)
        echo "Usage: sudo $0 {start|stop}"
        exit 1
        ;;
esac

exit 0
