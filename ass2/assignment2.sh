#!/bin/bash

# ===================================================================================
# Assignment 2 - Self-Contained Service Control Script (v4)
#
# This version automatically installs missing system and Python prerequisites
# on Debian/Ubuntu systems, making it even more self-sufficient.
#
# It assumes:
#   1. The network from `assignment1.sh` is already running.
#   2. You have a running PostgreSQL instance configured as per the assignment guide.
#
# Usage:
#   sudo ./assignment2.sh start   # Creates files and starts all services
#   sudo ./assignment2.sh stop    # Stops all services and deletes files
#   sudo ./assignment2.sh status  # Shows running service processes
# ===================================================================================

# Exit on any error
set -e

# --- Global variables for command paths ---
# Get the directory where the script is located, and use an absolute path
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VENV_DIR="$SCRIPT_DIR/networking_venv" # Create venv in the current directory
PYTHON_CMD=""
REDIS_SERVER_CMD=""
REDIS_CLI_CMD=""
NGINX_CMD=""

# --- Function to install missing prerequisites ---
install_prerequisites() {
    echo "--- Installing missing prerequisites ---"
    local packages_to_install=()

    # Define all required packages
    local required_packages=("nginx" "redis-server" "python3-pip" "python3-venv" "postgresql-client" "postgresql")
    
    # Check if apt-get is available
    if ! command -v apt-get >/dev/null; then
        echo "WARNING: apt-get not found. Cannot automatically install system packages." >&2
        echo "Please install the following packages manually: ${required_packages[*]}" >&2
        return 1 # Indicate failure
    fi

    # Check which packages are missing
    for pkg in "${required_packages[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
            packages_to_install+=("$pkg")
        fi
    done

    # Install missing packages if any
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        echo "Updating apt package list..."
        sudo apt-get update
        echo "Installing system packages: ${packages_to_install[*]}..."
        sudo apt-get install -y "${packages_to_install[@]}"
    fi

    # --- Auto-configure PostgreSQL ---
    # Find the main postgresql.conf file.
    PG_CONF=$(sudo find /etc/postgresql -name "postgresql.conf" | head -n 1)
    if [ -n "$PG_CONF" ]; then
        echo "Configuring PostgreSQL to accept network connections..."
        # Allow connections from all network interfaces
        sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"
        sudo sed -i "s/listen_addresses = 'localhost'/listen_addresses = '*'/" "$PG_CONF"

        # Find the pg_hba.conf file in the same directory
        PG_HBA_CONF="${PG_CONF%/*}/pg_hba.conf"
        
        # Add a rule to trust connections from our private network, if the rule doesn't already exist.
        if ! sudo grep -q "host    all             all             10.0.0.0/24             trust" "$PG_HBA_CONF"; then
            echo "Adding access rule to pg_hba.conf for 10.0.0.0/24 network..."
            echo "host    all             all             10.0.0.0/24             trust" | sudo tee -a "$PG_HBA_CONF" > /dev/null
        fi
        
        echo "Restarting PostgreSQL service to apply changes..."
        sudo systemctl restart postgresql
        sleep 2 # Give the service a moment to come back up

        # Create the 'orders' database if it doesn't exist.
        if ! sudo -u postgres psql -lqt | cut -d \| -f 1 | grep -qw orders; then
            echo "Creating 'orders' database..."
            sudo -u postgres createdb orders
        fi
    else
        echo "WARNING: postgresql.conf not found. Could not auto-configure PostgreSQL."
    fi

    # --- Configure Python Virtual Environment ---
    local system_python
    system_python=$(which python3 || true)
    if [ -z "$system_python" ]; then
        echo "ERROR: python3 command not found. Cannot create virtual environment." >&2
        return 1
    fi
    
    # Only create venv if it doesn't exist
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating Python virtual environment at $VENV_DIR..."
        "$system_python" -m venv "$VENV_DIR"
    fi

    # Install Python packages using the venv's pip
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
# This makes the script resilient to PATH issues and handles missing commands.
discover_commands() {
    echo "--- Discovering required command paths ---"

    local missing_any=0 # Flag to check if any command was missing

    # Python command should now point to the virtual environment
    PYTHON_CMD="$VENV_DIR/bin/python"
    if [ ! -x "$PYTHON_CMD" ]; then
        # If the venv python doesn't exist, we treat it as missing.
        echo "  - python3 (in venv): MISSING"
        missing_any=1
    fi

    REDIS_SERVER_CMD=$(which redis-server || true)
    if [ -z "$REDIS_SERVER_CMD" ]; then
        echo "  - redis-server: MISSING"
        missing_any=1
    fi

    REDIS_CLI_CMD=$(which redis-cli || true)
    if [ -z "$REDIS_CLI_CMD" ]; then
        echo "  - redis-cli: MISSING"
        missing_any=1
    fi

    NGINX_CMD=$(which nginx || true)
    if [ -z "$NGINX_CMD" ]; then
        echo "  - nginx: MISSING"
        missing_any=1
    fi

    if [ "$missing_any" -eq 1 ]; then
        echo "Some commands are missing. Attempting to install prerequisites..."
        if install_prerequisites; then
            echo "--- Re-discovering required command paths after installation ---"
            # Re-discover all commands to update their paths
            PYTHON_CMD="$VENV_DIR/bin/python" # Re-set python path
            REDIS_SERVER_CMD=$(which redis-server || true)
            REDIS_CLI_CMD=$(which redis-cli || true)
            NGINX_CMD=$(which nginx || true)

            # Final check after installation
            if [ ! -x "$PYTHON_CMD" ] || [ -z "$REDIS_SERVER_CMD" ] || [ -z "$REDIS_CLI_CMD" ] || [ -z "$NGINX_CMD" ]; then
                echo "ERROR: Some commands are still missing after installation attempt. Please check manually." >&2
                exit 1
            fi
        else
            echo "ERROR: Prerequisites installation failed. Please install manually." >&2
            exit 1
        fi
    fi

    echo "✅ All required commands found."
    echo "   - Python: $PYTHON_CMD"
    echo "   - Nginx: $NGINX_CMD"
    echo "   - Redis Server: $REDIS_SERVER_CMD"
    echo "   - Redis CLI: $REDIS_CLI_CMD"
}

# --- Function to create all application files ---
create_files() {
    echo "--- Creating application source files ---"
    
    cat <<'EOF' > nginx.conf
events {
    worker_connections 1024;
}
http {
    upstream api_gateway {
        server 10.0.0.20:3000;
    }
    server {
        listen 80;
        server_name localhost;
        location / {
            proxy_pass http://api_gateway;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
        location /health {
            return 200 "OK (nginx-lb)\n";
            add_header Content-Type text/plain;
        }
    }
}
EOF
    cat <<'EOF' > api-gateway.py
from flask import Flask, jsonify, request
import requests
import os
app = Flask(__name__)
PRODUCT_SERVICE = os.getenv("PRODUCT_SERVICE_URL", "http://10.0.0.30:5000")
ORDER_SERVICE = os.getenv("ORDER_SERVICE_URL", "http://10.0.0.40:5000")
@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "api-gateway"})
@app.route('/api/products', methods=['GET'])
def get_products():
    try:
        response = requests.get(f"{PRODUCT_SERVICE}/products")
        response.raise_for_status()
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Product service is unavailable", "details": str(e)}), 503
@app.route('/api/products/<id>', methods=['GET'])
def get_product(id):
    try:
        response = requests.get(f"{PRODUCT_SERVICE}/products/{id}")
        response.raise_for_status()
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Product service is unavailable", "details": str(e)}), 503
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
    cat <<'EOF' > product-service.py
from flask import Flask, jsonify
import redis
import json
import os
app = Flask(__name__)
REDIS_HOST = os.getenv("REDIS_HOST", "10.0.0.50")
cache = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True)
PRODUCTS = {
    "1": {"id": "1", "name": "Laptop", "price": 999.99, "stock": 50},
    "2": {"id": "2", "name": "Mouse", "price": 29.99, "stock": 200},
    "3": {"id": "3", "name": "Keyboard", "price": 79.99, "stock": 150},
}
@app.route('/health')
def health():
    try:
        cache.ping()
        return jsonify({"status": "healthy", "service": "product-service", "cache": "connected"})
    except redis.exceptions.ConnectionError:
        return jsonify({"status": "unhealthy", "service": "product-service", "cache": "disconnected"}), 503
@app.route('/products', methods=['GET'])
def get_products():
    try:
        cached = cache.get('all_products')
        if cached:
            return jsonify(json.loads(cached))
    except redis.exceptions.ConnectionError:
        pass
    products = list(PRODUCTS.values())
    try:
        cache.setex('all_products', 30, json.dumps(products))
    except redis.exceptions.ConnectionError:
        pass
    return jsonify(products)
@app.route('/products/<product_id>', methods=['GET'])
def get_product(product_id):
    try:
        cached = cache.get(f'product_{product_id}')
        if cached:
            return jsonify(json.loads(cached))
    except redis.exceptions.ConnectionError:
        pass
    product = PRODUCTS.get(product_id)
    if not product:
        return jsonify({"error": "Product not found"}), 404
    try:
        cache.setex(f'product_{product_id}', 30, json.dumps(product))
    except redis.exceptions.ConnectionError:
        pass
    return jsonify(product)
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
    cat <<'EOF' > order-service.py
from flask import Flask, jsonify, request
import psycopg2
import os
import sys
app = Flask(__name__)
DB_HOST = os.getenv("DB_HOST", "10.0.0.1")
DB_NAME = os.getenv("DB_NAME", "orders")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")
def get_db():
    return psycopg2.connect(
        host=DB_HOST, database=DB_NAME,
        user=DB_USER, password=DB_PASSWORD
    )
def init_db():
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('''
            CREATE TABLE IF NOT EXISTS orders (
                id SERIAL PRIMARY KEY,
                customer_id VARCHAR(100) NOT NULL,
                product_id VARCHAR(100) NOT NULL,
                quantity INTEGER NOT NULL,
                total_price DECIMAL(10, 2) NOT NULL,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        conn.commit()
        cur.close()
        conn.close()
        print("Database initialized.", file=sys.stderr)
    except psycopg2.OperationalError as e:
        print(f"Could not connect to database or initialize schema: {e}", file=sys.stderr)
        sys.exit(1)
@app.route('/health')
def health():
    try:
        conn = get_db()
        conn.close()
        return jsonify({"status": "healthy", "service": "order-service", "database": "connected"})
    except psycopg2.OperationalError:
        return jsonify({"status": "unhealthy", "service": "order-service", "database": "disconnected"}), 503
@app.route('/orders', methods=['POST'])
def create_order():
    data = request.json
    if not data:
        return jsonify({"error": "Invalid JSON"}), 400
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute(
            '''INSERT INTO orders (customer_id, product_id, quantity, total_price)
               VALUES (%s, %s, %s, %s) RETURNING id''',
            (data['customer_id'], data['product_id'], data['quantity'], data['total_price'])
        )
        order_id = cur.fetchone()[0]
        conn.commit()
        cur.close()
        conn.close()
        return jsonify({"order_id": order_id, "status": "created"}), 201
    except (psycopg2.Error, KeyError) as e:
        return jsonify({"error": "Database error or invalid request data", "details": str(e)}), 500
if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
EOF
    echo "✅ Application files created."
}

# --- Function to delete all application files ---
delete_files() {
    echo "--- Deleting application source files ---"
    rm -f nginx.conf api-gateway.py product-service.py order-service.py
    echo "✅ Application files deleted."
}

# --- Function to start all services ---
start_services() {
    discover_commands # Ensure all commands are found/installed first
    create_files
    
    echo ""
    echo "--- Starting all services ---"

    echo "[1/5] Starting Redis server in 'redis-cache' namespace..."
    sudo ip netns exec redis-cache "$REDIS_SERVER_CMD" --bind 0.0.0.0 --port 6379 --daemonize yes
    sleep 1

    echo "[2/5] Starting API Gateway in 'api-gateway' namespace..."
    sudo ip netns exec api-gateway "$PYTHON_CMD" api-gateway.py &
    
    echo "[3/5] Starting Product Service in 'product-service' namespace..."
    sudo ip netns exec product-service "$PYTHON_CMD" product-service.py &

    echo "[4/5] Starting Order Service in 'order-service' namespace..."
    sudo ip netns exec order-service "$PYTHON_CMD" order-service.py &
    sleep 1

    echo "[5/5] Starting Nginx in 'nginx-lb' namespace..."
    sudo mkdir -p /tmp/nginx
    sudo cp nginx.conf /tmp/nginx/nginx.conf
    sudo ip netns exec nginx-lb "$NGINX_CMD" -c /tmp/nginx/nginx.conf

    echo ""
    echo "✅ All services started."
    echo "Run 'sudo ./assignment2.sh status' to see the running processes."
}

# --- Function to stop all services ---
stop_services() {
    discover_commands # Make sure we can find commands before trying to stop them
    echo "--- Stopping all services ---"

    echo "[1/5] Stopping Nginx..."
    sudo ip netns exec nginx-lb "$NGINX_CMD" -s stop 2>/dev/null || pkill -f "nginx: master process" || true

    echo "[2/5] Stopping Python microservices..."
    pkill -f "api-gateway.py" || true
    pkill -f "product-service.py" || true
    pkill -f "order-service.py" || true

    echo "[3/5] Stopping Redis server..."
    sudo ip netns exec redis-cache "$REDIS_CLI_CMD" shutdown 2>/dev/null || pkill -f "$REDIS_SERVER_CMD" || true

    echo "[4/5] Cleaning up Nginx config and Python venv..."
    sudo rm -rf /tmp/nginx
    rm -rf "$VENV_DIR"

    echo "[5/5] Deleting source files..."
    delete_files
    
    echo ""
    echo "✅ All services stopped and files cleaned up."
}

# --- Function to check the status of services ---
status_services() {
    discover_commands # Make sure we can find commands before checking their status
    echo "--- Checking service status ---"
    echo ""
    echo "=> Nginx Processes:"
    # Use a pattern that won't match the pgrep command itself
    sudo ip netns exec nginx-lb pgrep -af "nginx: master process" || echo "  Not running."
    echo ""
    echo "=> Python App Processes (api-gateway.py):"
    sudo ip netns exec api-gateway pgrep -af "[a]pi-gateway.py" || echo "  Not running."
    echo ""
    echo "=> Python App Processes (product-service.py):"
    sudo ip netns exec product-service pgrep -af "[p]roduct-service.py" || echo "  Not running."
    echo ""
    echo "=> Python App Processes (order-service.py):"
    sudo ip netns exec order-service pgrep -af "[o]rder-service.py" || echo "  Not running."
    echo ""
    echo "=> Redis Process:"
    sudo ip netns exec redis-cache pgrep -af "[r]edis-server" || echo "  Not running."
    echo ""
}

# --- Main script logic ---
case "$1" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    status)
        status_services
        ;;
    *)
        echo "Usage: sudo $0 {start|stop|status}"
        exit 1
        ;;
esac

exit 0
