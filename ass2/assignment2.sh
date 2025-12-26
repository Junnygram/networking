#!/bin/bash

# NOTE: If you see an error like "sudo: unable to resolve host...",
# it is a system configuration issue. This script will attempt to automatically
# fix it by adding the hostname to /etc/hosts.

# ===================================================================================
# Assignment 2 - Self-Contained Service Control Script (v6 - Stable)
#
# This version provides a stable, reliable, and idempotent script for managing
# the microservices environment. It fixes all identified startup race conditions,
# host configuration errors, and process management flaws.
#
# Usage:
#   sudo ./assignment2.sh start     # Idempotent start: cleans up old processes and starts all services.
#   sudo ./assignment2.sh stop      # Stops all running service processes.
#   sudo ./assignment2.sh restart   # Stops and then starts all services.
#   sudo ./assignment2.sh status    # Shows running service processes.
#   sudo ./assignment2.sh clean     # Deletes all generated files and the Python venv.
# ===================================================================================

# Exit on any error
set -e

# --- Function to fix /etc/hosts for sudo ---
fix_etc_hosts() {
    local hostname
    hostname=$(hostname)
    if ! grep -q "127.0.0.1.*$hostname" /etc/hosts; then
        echo "--- Checking /etc/hosts for hostname resolution ---"
        echo "Hostname '$hostname' not found for 127.0.0.1. Attempting to add it."
        if ! sudo sed -i.bak "s/^\(127\.0\.0\.1\s*localhost\).*/\1 $hostname/" /etc/hosts; then
             echo "WARNING: Failed to automatically patch /etc/hosts. Sudo errors may persist." >&2
        else
             echo "✅ Hostname added to /etc/hosts. This should resolve 'sudo' errors."
        fi
    fi
}

# --- Global variables for command paths ---
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VENV_DIR="$SCRIPT_DIR/networking_venv"
PYTHON_CMD=""
REDIS_SERVER_CMD=""
REDIS_CLI_CMD=""
NGINX_CMD=""

# --- Function to install missing prerequisites ---
install_prerequisites() {
    echo "--- Installing missing prerequisites ---"
    local packages_to_install=()
    local required_packages=("nginx" "redis-server" "python3-pip" "python3-venv" "postgresql-client" "postgresql")
    if ! command -v apt-get >/dev/null; then
        echo "WARNING: apt-get not found. Cannot automatically install system packages." >&2
        return 1
    fi
    for pkg in "${required_packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            packages_to_install+=("$pkg")
        fi
    done
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        echo "Updating apt package list..."
        sudo apt-get update
        echo "Installing system packages: ${packages_to_install[*]}..."
        sudo apt-get install -y "${packages_to_install[@]}"
    fi
    PG_CONF=$(sudo find /etc/postgresql -name "postgresql.conf" | head -n 1)
    if [ -n "$PG_CONF" ]; then
        echo "Configuring PostgreSQL to accept network connections..."
        sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
        sudo sed -i "s/listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
        PG_HBA_CONF="${PG_CONF%/*}/pg_hba.conf"
        if ! sudo grep -q "host    all             all             10.0.0.0/24             trust" "$PG_HBA_CONF"; then
            echo "Adding access rule to pg_hba.conf for 10.0.0.0/24 network..."
            echo "host    all             all             10.0.0.0/24             trust" | sudo tee -a "$PG_HBA_CONF" > /dev/null
        fi
        echo "Restarting PostgreSQL service to apply changes..."
        sudo systemctl restart postgresql
        sleep 2
        if ! sudo -u postgres psql -lqt | cut -d '|' -f 1 | grep -qw orders; then
            echo "Creating 'orders' database..."
            sudo -u postgres createdb orders
        fi
    else
        echo "WARNING: postgresql.conf not found. Could not auto-configure PostgreSQL."
    fi
    local system_python
    system_python=$(which python3 || true)
    if [ -z "$system_python" ]; then
        echo "ERROR: python3 command not found. Cannot create virtual environment." >&2
        return 1
    fi
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating Python virtual environment at $VENV_DIR..."
        "$system_python" -m venv "$VENV_DIR"
    fi
    VENV_PYTHON="$VENV_DIR/bin/python"
    if [ -x "$VENV_PYTHON" ]; then
        echo "Installing/updating Python packages: Flask, requests, psycopg2-binary, redis..."
        "$VENV_PYTHON" -m pip install -U Flask requests psycopg2-binary redis
    else
        echo "ERROR: Virtual environment Python executable not found at $VENV_PYTHON." >&2
        return 1
    fi
    echo "✅ Prerequisites installation and configuration attempted."
    return 0
}

# --- Discover Executable Paths ---
discover_commands() {
    local missing_any=0
    PYTHON_CMD="$VENV_DIR/bin/python"
    if [ ! -x "$PYTHON_CMD" ]; then missing_any=1; fi
    REDIS_SERVER_CMD=$(which redis-server || true)
    if [ -z "$REDIS_SERVER_CMD" ]; then missing_any=1; fi
    REDIS_CLI_CMD=$(which redis-cli || true)
    if [ -z "$REDIS_CLI_CMD" ]; then missing_any=1; fi
    NGINX_CMD=$(which nginx || true)
    if [ -z "$NGINX_CMD" ]; then missing_any=1; fi
    if [ "$missing_any" -eq 1 ]; then
        echo "Some commands are missing or venv not created. Attempting to install prerequisites..."
        if ! install_prerequisites; then
            echo "ERROR: Prerequisites installation failed. Please install manually." >&2
            exit 1
        fi
        # Re-discover after install
        PYTHON_CMD="$VENV_DIR/bin/python"
        REDIS_SERVER_CMD=$(which redis-server || true)
        REDIS_CLI_CMD=$(which redis-cli || true)
        NGINX_CMD=$(which nginx || true)
    fi
    echo "✅ All required commands found."
}

# --- Function to create all application files ---
create_files() {
    if [ -f "$SCRIPT_DIR/api-gateway.py" ]; then
        return
    fi
    echo "--- Creating application source files in $SCRIPT_DIR ---"
    cat <<'EOF' > "$SCRIPT_DIR/nginx.conf"
events { worker_connections 1024; }
http {
    upstream api_gateway { server 10.0.0.20:3000; }
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
    cat <<'EOF' > "$SCRIPT_DIR/api-gateway.py"
from flask import Flask, jsonify, request
import requests, os
app = Flask(__name__)
PRODUCT_SERVICE = os.getenv("PRODUCT_SERVICE_URL", "http://10.0.0.30:5000")
ORDER_SERVICE = os.getenv("ORDER_SERVICE_URL", "http://10.0.0.40:5000")
@app.route('/health')
def health(): return jsonify({"status": "healthy", "service": "api-gateway"})
@app.route('/api/products', methods=['GET'])
def get_products():
    try:
        res = requests.get(f"{PRODUCT_SERVICE}/products")
        res.raise_for_status()
        return jsonify(res.json()), res.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Product service is unavailable", "details": str(e)}), 503
@app.route('/api/orders', methods=['POST'])
def create_order():
    try:
        res = requests.post(f"{ORDER_SERVICE}/orders", json=request.json)
        res.raise_for_status()
        return jsonify(res.json()), res.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Order service is unavailable", "details": str(e)}), 503
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False)
EOF
    cat <<'EOF' > "$SCRIPT_DIR/product-service.py"
from flask import Flask, jsonify
import redis, json, os, time, sys
app = Flask(__name__)
REDIS_HOST = os.getenv("REDIS_HOST", "10.0.0.50")
cache = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True, socket_connect_timeout=2)
PRODUCTS = {
    "1": {"id": "1", "name": "Laptop", "price": 999.99},
    "2": {"id": "2", "name": "Mouse", "price": 29.99},
}
def wait_for_redis():
    retries = 30
    print("--- Checking for Redis connectivity ---", file=sys.stderr)
    while retries > 0:
        try:
            cache.ping()
            print("✅ Successfully connected to Redis.", file=sys.stderr)
            return True
        except redis.exceptions.ConnectionError:
            print(f"Waiting for Redis... ({retries} retries left)", file=sys.stderr)
            retries -= 1
            time.sleep(2)
    print("❌ Could not connect to Redis. Exiting.", file=sys.stderr)
    return False
@app.route('/health')
def health():
    try:
        cache.ping()
        return jsonify({"status": "healthy", "cache": "connected"})
    except redis.exceptions.ConnectionError:
        return jsonify({"status": "unhealthy", "cache": "disconnected"}), 503
@app.route('/products', methods=['GET'])
def get_products(): return jsonify(list(PRODUCTS.values()))
@app.route('/products/<product_id>', methods=['GET'])
def get_product(product_id):
    prod = PRODUCTS.get(product_id)
    return jsonify(prod) if prod else (jsonify({"error": "Not found"}), 404)
if __name__ == '__main__':
    if wait_for_redis():
        try:
            app.run(host='0.0.0.0', port=5000, debug=False)
        except Exception as e:
            print(f"CRITICAL: Failed to start Flask app: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        sys.exit(1)
EOF
    cat <<'EOF' > "$SCRIPT_DIR/order-service.py"
from flask import Flask, jsonify, request
import psycopg2, os, sys
app = Flask(__name__)
DB_HOST = os.getenv("DB_HOST", "10.0.0.1")
def get_db():
    return psycopg2.connect(host=DB_HOST, dbname="orders", user="postgres", password="postgres")
def init_db():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('CREATE TABLE IF NOT EXISTS orders (id SERIAL PRIMARY KEY, customer_id TEXT, total_price REAL);')
        conn.commit()
    except psycopg2.OperationalError as e:
        print(f"Could not connect to database: {e}", file=sys.stderr)
        sys.exit(1)
@app.route('/health')
def health():
    try:
        get_db().close()
        return jsonify({"status": "healthy", "database": "connected"})
    except psycopg2.OperationalError:
        return jsonify({"status": "unhealthy", "database": "disconnected"}), 503
@app.route('/orders', methods=['POST'])
def create_order():
    data = request.json
    conn = get_db()
    cur = conn.cursor()
    cur.execute('INSERT INTO orders (customer_id, total_price) VALUES (%s, %s) RETURNING id', (data['customer_id'], data['total_price']))
    order_id = cur.fetchone()[0]
    conn.commit()
    return jsonify({"order_id": order_id}), 201
if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF
    chmod +x "$SCRIPT_DIR"/*.py
    echo "✅ Application files created."
}

# --- Function to stop service processes ---
stop_procs() {
    echo "--- Stopping all service processes ---"
    # Use a broad pkill to catch all nginx processes, then target specific scripts
    sudo pkill -9 -f "nginx" || true
    sudo pkill -9 -f "api-gateway.py" || true
    sudo pkill -9 -f "product-service.py" || true
    sudo pkill -9 -f "order-service.py" || true
    sudo pkill -9 -f "redis-server 0.0.0.0:6379" || true
    echo "✅ Processes stopped."
}

# --- Function to start all services (Idempotent) ---
start_services() {
    fix_etc_hosts
    discover_commands
    create_files
    # ensure_python_packages is called by discover_commands if needed

    stop_procs # Ensure clean state before starting
    
    echo "--- Starting all services ---"
    echo "[1/5] Starting Redis server..."
    sudo ip netns exec redis-cache "$REDIS_SERVER_CMD" --bind 0.0.0.0 --port 6379 --daemonize yes --protected-mode no
    sleep 3

    echo "--- Running network diagnostics ---"
    if ! sudo ip netns exec product-service ping -c 2 10.0.0.50; then
        echo "ERROR: Cannot ping redis-cache from product-service." >&2
        exit 1
    fi
    echo "✅ Ping successful."

    echo "[2/5] Starting API Gateway..."
    sudo ip netns exec api-gateway "$PYTHON_CMD" "$SCRIPT_DIR/api-gateway.py" > /tmp/api-gateway.log 2>&1 &
    
    echo "[3/5] Starting Product Service..."
    sudo ip netns exec product-service "$PYTHON_CMD" "$SCRIPT_DIR/product-service.py" > /tmp/product-service.log 2>&1 &

    echo "[4/5] Starting Order Service..."
    sudo ip netns exec order-service "$PYTHON_CMD" "$SCRIPT_DIR/order-service.py" > /tmp/order-service.log 2>&1 &
    sleep 2

    echo "[5/5] Starting Nginx..."
    sudo mkdir -p /tmp/nginx
    sudo cp "$SCRIPT_DIR/nginx.conf" /tmp/nginx/nginx.conf
    sudo ip netns exec nginx-lb "$NGINX_CMD" -c /tmp/nginx/nginx.conf

    echo "✅ All services started."
}

# --- Function to check service status ---
status_services() {
    echo "--- Checking service status ---"
    # Use pgrep -af "[p]attern" to avoid matching the pgrep command itself
    echo; echo "=> Nginx Processes:"; sudo pgrep -af "[n]ginx" || echo "  Not running."
    echo; echo "=> API Gateway Processes:"; sudo pgrep -af "[a]pi-gateway.py" || echo "  Not running."
    echo; echo "=> Product Service Processes:"; sudo pgrep -af "[p]roduct-service.py" || echo "  Not running."
    echo; echo "=> Order Service Processes:"; sudo pgrep -af "[o]rder-service.py" || echo "  Not running."
    echo; echo "=> Redis Processes:"; sudo pgrep -af "[r]edis-server" || echo "  Not running."
    echo
}

# --- Function to clean up generated files ---
clean_files() {
    echo "--- Deleting all generated files and Python venv ---"
    sudo rm -rf /tmp/nginx
    rm -rf "$VENV_DIR"
    rm -f "$SCRIPT_DIR/nginx.conf"
    rm -f "$SCRIPT_DIR/api-gateway.py"
    rm -f "$SCRIPT_DIR/product-service.py"
    rm -f "$SCRIPT_DIR/order-service.py"
    rm -f /tmp/*.log 2>/dev/null || true
    echo "✅ Cleanup complete."
}

# --- Main script logic ---
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_procs
        ;;
    restart)
        start_services # Start is now idempotent, so it's the same as restart
        ;;
    status)
        status_services
        ;;
    clean)
        stop_procs
        clean_files
        ;;
    *)
        echo "Usage: sudo $0 {start|stop|restart|status|clean}"
        exit 1
        ;;
esac

exit 0