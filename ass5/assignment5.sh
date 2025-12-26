#!/bin/bash

# ===================================================================================
# Assignment 5 - Docker Migration Toolkit
#
# This script automates the Docker migration and orchestration tasks using Docker Compose.
# It generates Dockerfiles, a docker-compose.yml, and provides commands to build,
# start, stop, and benchmark the Dockerized application.
#
# Usage:
#   sudo ./assignment5.sh {start|stop|benchmark|clean}
#
# Commands:
#   start     - Generates Dockerfiles & docker-compose.yml, builds images, and starts containers.
#   stop      - Stops and removes containers, networks, and generated files.
#   benchmark - Runs ApacheBench against the Dockerized application.
#   clean     - Removes all generated Docker-related files.
#
# Note: Ensure Docker and Docker Compose are installed before running this script.
# ===================================================================================

set -e

# --- Global variables for command paths ---
DOCKER_CMD=""
DOCKER_COMPOSE_CMD=""
AB_CMD=""

# --- Discover Executable Paths ---
discover_commands() {
    echo "--- Discovering required command paths (Docker, Docker Compose, ab) ---"

    local missing_any=0 # Flag to check if any command was missing

    DOCKER_CMD=$(which docker || true)
    if [ -z "$DOCKER_CMD" ]; then
        echo "  - docker: MISSING"
        echo "    Please install Docker Engine: https://docs.docker.com/engine/install/" >&2
        missing_any=1
    fi

    DOCKER_COMPOSE_CMD=$(which docker-compose || which docker || true) # Try docker-compose then docker for v1 vs v2
    if [ -z "$DOCKER_COMPOSE_CMD" ]; then
        echo "  - docker-compose: MISSING"
        echo "    Please install Docker Compose: https://docs.docker.com/compose/install/" >&2
        missing_any=1
    elif [ "$DOCKER_COMPOSE_CMD" == "$(which docker || true)" ]; then
        DOCKER_COMPOSE_CMD="$DOCKER_COMPOSE_CMD compose" # Use 'docker compose' for v2
    fi

    AB_CMD=$(which ab || true)
    if [ -z "$AB_CMD" ]; then
        echo "  - ab (ApacheBench): MISSING"
        echo "    Please install apache2-utils: sudo apt-get install -y apache2-utils" >&2
        missing_any=1
    fi

    if [ "$missing_any" -eq 1 ]; then
        echo "ERROR: Some required commands are missing. Please install them manually." >&2
        exit 1
    fi

    echo "✅ All required commands found."
    echo "   - Docker: $DOCKER_CMD"
    echo "   - Docker Compose: $DOCKER_COMPOSE_CMD"
    echo "   - ApacheBench (ab): $AB_CMD"
}

# --- Function to generate Dockerfiles and docker-compose.yml ---
generate_docker_files() {
    echo "--- Generating Docker-related files ---"

    # requirements.txt for Python apps
    cat <<'EOF' > requirements.txt
Flask
requests
psycopg2-binary
redis
EOF

    # Dockerfile.nginx-lb
    cat <<'EOF' > Dockerfile.nginx-lb
FROM nginx:alpine
WORKDIR /etc/nginx/conf.d
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF

    # Dockerfile.api-gateway
    cat <<'EOF' > Dockerfile.api-gateway
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api-gateway.py .
EXPOSE 3000
CMD ["python", "api-gateway.py"]
EOF

    # Dockerfile.product-service
    cat <<'EOF' > Dockerfile.product-service
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY product-service.py .
EXPOSE 5000
CMD ["python", "product-service.py"]
EOF

    # Dockerfile.order-service
    cat <<'EOF' > Dockerfile.order-service
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY order-service.py .
EXPOSE 5000
CMD ["python", "order-service.py"]
EOF

    # docker-compose.yml
    cat <<'EOF' > docker-compose.yml
version: '3.8'

services:
  nginx-lb:
    build:
      context: .
      dockerfile: Dockerfile.nginx-lb
    ports:
      - "8080:80"
    networks:
      - frontend_net
    depends_on:
      - api-gateway

  api-gateway:
    build:
      context: .
      dockerfile: Dockerfile.api-gateway
    networks:
      - frontend_net
      - backend_net
    depends_on:
      - product-service
      - order-service

  product-service:
    build:
      context: .
      dockerfile: Dockerfile.product-service
    networks:
      - backend_net
      - cache_net
    depends_on:
      - redis-cache
    deploy:
      replicas: 3
    environment:
      REDIS_HOST: redis-cache

  order-service:
    build:
      context: .
      dockerfile: Dockerfile.order-service
    networks:
      - backend_net
      - database_net
    depends_on:
      - postgres-db
    environment:
      DB_HOST: postgres-db
      DB_NAME: orders
      DB_USER: postgres
      DB_PASSWORD: postgres

  redis-cache:
    image: redis:alpine
    networks:
      - cache_net

  postgres-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - database_net

networks:
  frontend_net:
    driver: bridge
  backend_net:
    driver: bridge
  cache_net:
    driver: bridge
  database_net:
    driver: bridge

volumes:
  postgres_data:
EOF

    # Copy actual Python app files (from assignment2) and nginx.conf
    # This assumes assignment2.sh was run at least once to create these.
    # If not, the user needs to create them or this part needs more robust HEREDOCs.
    # For now, let's include the HEREDOCs for simplicity.
    cat <<'EOF' > api-gateway.py
from flask import Flask, jsonify, request
import requests
import os
app = Flask(__name__)
PRODUCT_SERVICE = os.getenv("PRODUCT_SERVICE_URL", "http://product-service:5000")
ORDER_SERVICE = os.getenv("ORDER_SERVICE_URL", "http://order-service:5000")
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
import time
import sys

app = Flask(__name__)
REDIS_HOST = os.getenv("REDIS_HOST", "redis-cache")
cache = redis.Redis(host=REDIS_HOST, port=6379, decode_responses=True, socket_connect_timeout=2)

PRODUCTS = {
    "1": {"id": "1", "name": "Laptop", "price": 999.99, "stock": 50},
    "2": {"id": "2", "name": "Mouse", "price": 29.99, "stock": 200},
    "3": {"id": "3", "name": "Keyboard", "price": 79.99, "stock": 150},
}

def wait_for_redis():
    """Wait for redis to become available."""
    retries = 15
    print("--- Checking for Redis connectivity ---", file=sys.stderr)
    while retries > 0:
        try:
            cache.ping()
            print("✅ Successfully connected to Redis.", file=sys.stderr)
            return True
        except redis.exceptions.ConnectionError as e:
            print(f"Waiting for Redis... ({retries} retries left)", file=sys.stderr)
            retries -= 1
            time.sleep(2)
    print("❌ Could not connect to Redis after multiple retries. Exiting.", file=sys.stderr)
    return False

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
    if wait_for_redis():
        app.run(host='0.0.0.0', port=5000)
    else:
        sys.exit(1)
EOF
    cat <<'EOF' > order-service.py
from flask import Flask, jsonify, request
import psycopg2
import os
import sys
import time

app = Flask(__name__)
DB_HOST = os.getenv("DB_HOST", "postgres-db")
DB_NAME = os.getenv("DB_NAME", "orders")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "postgres")

def get_db_connection():
    return psycopg2.connect(
        host=DB_HOST, database=DB_NAME,
        user=DB_USER, password=DB_PASSWORD
    )

def wait_for_db():
    """Wait for the database to become available."""
    retries = 15
    print("--- Checking for Database connectivity ---", file=sys.stderr)
    while retries > 0:
        try:
            conn = get_db_connection()
            conn.close()
            print("✅ Successfully connected to Database.", file=sys.stderr)
            return True
        except psycopg2.OperationalError as e:
            print(f"Waiting for Database... ({retries} retries left)", file=sys.stderr)
            retries -= 1
            time.sleep(2)
    print("❌ Could not connect to Database after multiple retries. Exiting.", file=sys.stderr)
    return False

def init_db():
    conn = get_db_connection()
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
    print("Database schema initialized.", file=sys.stderr)

@app.route('/health')
def health():
    try:
        conn = get_db_connection()
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
        conn = get_db_connection()
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
    if wait_for_db():
        init_db()
        app.run(host='0.0.0.0', port=5000)
    else:
        sys.exit(1)
EOF
    cat <<'EOF' > nginx.conf
events {
    worker_connections 1024;
}
http {
    upstream api_gateway {
        server api-gateway:3000;
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

    echo "✅ Docker-related files generated."
}

# --- Function to delete Dockerfiles and docker-compose.yml ---
clean_docker_files() {
    echo "--- Cleaning up Docker-related files ---"
    rm -f requirements.txt Dockerfile.nginx-lb Dockerfile.api-gateway \
          Dockerfile.product-service Dockerfile.order-service \
          docker-compose.yml api-gateway.py product-service.py \
          order-service.py nginx.conf
    echo "✅ Docker-related files cleaned."
}

# --- Function to start Dockerized application ---
start_docker_app() {
    generate_docker_files
    echo "--- Building Docker images and starting containers ---"
    "$DOCKER_COMPOSE_CMD" build
    "$DOCKER_COMPOSE_CMD" up -d
    echo ""
    echo "✅ Dockerized application started on http://localhost:8080"
}

# --- Function to stop Dockerized application ---
stop_docker_app() {
    echo "--- Stopping and removing Docker containers ---"
    "$DOCKER_COMPOSE_CMD" down --volumes
    clean_docker_files
    echo "✅ Dockerized application stopped."
}

# --- Function to run benchmark ---
run_benchmark() {
    echo "--- Running performance benchmark ---"
    echo "Benchmarking Docker implementation..."
    "$AB_CMD" -n 1000 -c 100 http://localhost:8080/api/products

    echo "✅ Benchmark complete."
    echo "Note: For a comparison benchmark, ensure the Linux primitive setup"
    echo "      is also configured and accessible on http://localhost:8080"
}

# --- Main script logic ---
discover_commands # Ensure Docker/Compose/ab are available

case "$1" in
    start)
        start_docker_app
        ;;    stop)
        stop_docker_app
        ;;    benchmark)
        run_benchmark
        ;;    clean)
        clean_docker_files
        ;;    *)
        echo "Usage: sudo $0 {start|stop|benchmark|clean}"
        exit 1
        ;;esac

exit 0
