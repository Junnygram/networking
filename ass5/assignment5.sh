#!/bin/bash

# ===================================================================================
# Assignment 5 - Docker Migration Toolkit (v3 - with Auto-Install & Restart Prompt)
#
# This script automates the Docker migration and orchestration tasks. It now
# attempts to automatically install its own prerequisites (Docker, Docker Compose,
# and ApacheBench) on Debian/Ubuntu systems. It also includes robust,
# dependency-aware application code to prevent startup race conditions.
# It explicitly prompts for a shell restart if Docker is newly installed.
#
# Usage:
#   sudo ./ass5.sh {start|stop|benchmark|clean}
#
# ===================================================================================

set -e

# --- Global variables for command paths ---
DOCKER_CMD=""
DOCKER_COMPOSE_CMD=""
AB_CMD=""

# --- Prerequisite Installation ---
install_prerequisites() {
    echo "--- Attempting to install missing prerequisites... ---"
    local docker_installed_this_run=false
    
    if ! command -v apt-get >/dev/null; then
        echo "ERROR: apt-get not found. Cannot automatically install packages." >&2
        return 1
    fi

    sudo apt-get update

    # Install ApacheBench (ab) if missing
    if ! command -v ab >/dev/null; then
        echo "Installing apache2-utils (for ApacheBench)..."
        sudo apt-get install -y apache2-utils
    fi

    # Install Docker and Docker Compose if missing
    if ! command -v docker >/dev/null; then
        echo "Installing Docker Engine and Docker Compose..."
        docker_installed_this_run=true
        # This follows the official Docker installation guide for Debian/Ubuntu
        sudo apt-get install -y ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        if sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; then
            sudo chmod a+r /etc/apt/keyrings/docker.asc

            echo \
              "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
              $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
              sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

            echo "Adding current user to the 'docker' group..."
            sudo usermod -aG docker "$USER"
            echo "IMPORTANT: You MUST start a new shell session (or run 'newgrp docker') for group changes to take effect."
        else
            echo "ERROR: Failed to download Docker GPG key. Cannot install Docker automatically." >&2
            return 1
        fi
    fi
    # If Docker was installed in this run, we need a shell restart, so exit.
    if "$docker_installed_this_run"; then
        echo "--- Docker was just installed. Please restart your shell (log out/in or 'newgrp docker') before running this script again. ---"
        exit 1
    fi
    return 0
}


# --- Discover Executable Paths ---
discover_commands() {
    echo "--- Discovering required command paths (Docker, Docker Compose, ab) ---"
    
    # Attempt to install any missing prerequisites
    install_prerequisites

    local missing_any_after_install=0

    # Now check again after install attempt
    DOCKER_CMD=$(which docker || true)
    if [ -z "$DOCKER_CMD" ]; then
        echo "  - docker: MISSING (after install attempt)"
        missing_any_after_install=1
    fi

    if docker compose version >/dev/null 2>&1; then
        DOCKER_COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    else
        echo "  - docker-compose: MISSING (after install attempt)"
        missing_any_after_install=1
    fi

    AB_CMD=$(which ab || true)
    if [ -z "$AB_CMD" ]; then
        echo "  - ab (ApacheBench): MISSING (after install attempt)"
        missing_any_after_install=1
    fi

    if [ "$missing_any_after_install" -eq 1 ]; then
        echo "ERROR: Some required commands are still missing after installation attempt. Please check manually." >&2
        exit 1
    fi

    # Final check for docker group membership
    if ! docker info >/dev/null 2>&1; then
        echo "ERROR: Docker daemon is not running or your user is not in the 'docker' group. Please restart your shell (log out/in or 'newgrp docker')." >&2
        exit 1
    fi

    echo "✅ All required commands found."
}

# --- Function to generate Dockerfiles and robust application code ---
generate_docker_files() {
    echo "--- Generating Docker-related files with robust application code ---"

    cat <<'EOF' > requirements.txt
Flask
requests
psycopg2-binary
redis
EOF

    # Dockerfiles (no changes needed)
    cat <<'EOF' > Dockerfile.nginx-lb
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF
    cat <<'EOF' > Dockerfile.api-gateway
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api-gateway.py .
EXPOSE 3000
CMD ["python", "api-gateway.py"]
EOF
    cat <<'EOF' > Dockerfile.product-service
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY product-service.py .
EXPOSE 5000
CMD ["python", "product-service.py"]
EOF
    cat <<'EOF' > Dockerfile.order-service
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY order-service.py .
EXPOSE 5000
CMD ["python", "order-service.py"]
EOF

    # docker-compose.yml with healthchecks
    cat <<'EOF' > docker-compose.yml
version: '3.8'
services:
  nginx-lb:
    build: { context: ., dockerfile: Dockerfile.nginx-lb }
    ports: [ "8080:80" ]
    networks: [ frontend_net ]
    depends_on:
      api-gateway:
        condition: service_healthy
  api-gateway:
    build: { context: ., dockerfile: Dockerfile.api-gateway }
    networks: [ frontend_net, backend_net ]
    depends_on:
      product-service:
        condition: service_healthy
      order-service:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 5s
      timeout: 2s
      retries: 5
  product-service:
    build: { context: ., dockerfile: Dockerfile.product-service }
    networks: [ backend_net, cache_net ]
    depends_on:
      redis-cache:
        condition: service_healthy
    environment: { REDIS_HOST: redis-cache }
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 5s
      timeout: 2s
      retries: 5
  order-service:
    build: { context: ., dockerfile: Dockerfile.order-service }
    networks: [ backend_net, database_net ]
    depends_on:
      postgres-db:
        condition: service_healthy
    environment:
      DB_HOST: postgres-db
      POSTGRES_DB: orders
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    healthcheck:
      test: ["CMD", "python", "-c", "import sys, psycopg2; sys.exit(0) if psycopg2.connect(host='postgres-db', dbname='orders', user='postgres', password='postgres') else sys.exit(1)"]
      interval: 5s
      timeout: 3s
      retries: 5
  redis-cache:
    image: redis:7-alpine
    networks: [ cache_net ]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 2s
      retries: 5
  postgres-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes: [ postgres_data:/var/lib/postgresql/data ]
    networks: [ database_net ]
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "postgres", "-d", "orders"]
      interval: 5s
      timeout: 2s
      retries: 5
networks:
  frontend_net:
  backend_net:
  cache_net:
  database_net:
volumes:
  postgres_data:
EOF

    # Nginx config (targets service name)
    cat <<'EOF' > nginx.conf
events { worker_connections 1024; }
http {
    upstream api_gateway { server api-gateway:3000; }
    server {
        listen 80;
        location / {
            proxy_pass http://api_gateway;
        }
        location /health { return 200 "OK"; }
    }
}
EOF

    # --- Robust Python Application Code ---
    cat <<'EOF' > api-gateway.py
from flask import Flask, jsonify, request
import requests, os
app = Flask(__name__)
PRODUCT_SERVICE = os.getenv("PRODUCT_SERVICE_URL", "http://product-service:5000")
ORDER_SERVICE = os.getenv("ORDER_SERVICE_URL", "http://order-service:5000")
@app.route('/health')
def health(): return jsonify({"status": "healthy"})
@app.route('/api/products')
def get_products():
    res = requests.get(f"{PRODUCT_SERVICE}/products")
    return res.content, res.status_code
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False)
EOF
    cat <<'EOF' > product-service.py
from flask import Flask, jsonify
import redis, os, time, sys
app = Flask(__name__)
def get_redis_connection():
    return redis.Redis(host=os.getenv("REDIS_HOST", "redis-cache"), port=6379, decode_responses=True, socket_connect_timeout=2)
def wait_for_redis():
    retries = 30
    while retries > 0:
        try:
            get_redis_connection().ping()
            return True
        except redis.exceptions.ConnectionError:
            print(f"Waiting for Redis... ({retries} retries left)", file=sys.stderr)
            retries -= 1
            time.sleep(3)
    return False
@app.route('/health')
def health():
    try:
        get_redis_connection().ping()
        return jsonify({"status": "healthy"})
    except redis.exceptions.ConnectionError:
        return jsonify({"status": "unhealthy"}), 503
@app.route('/products')
def get_products():
    return jsonify([{"id": "1", "name": "Dockerized Laptop"}])
if __name__ == '__main__':
    if not wait_for_redis():
        sys.exit(1)
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF
    cat <<'EOF' > order-service.py
from flask import Flask, jsonify
import psycopg2, os, sys, time
app = Flask(__name__)
def get_db():
    return psycopg2.connect(host=os.getenv("DB_HOST"), dbname=os.getenv("POSTGRES_DB"), user=os.getenv("POSTGRES_USER"), password=os.getenv("POSTGRES_PASSWORD"), connect_timeout=3)
def wait_for_db():
    retries = 30
    while retries > 0:
        try:
            get_db().close()
            return True
        except psycopg2.OperationalError:
            print(f"Waiting for DB... ({retries} retries left)", file=sys.stderr)
            retries -= 1
            time.sleep(3)
    return False
@app.route('/health')
def health():
    try:
        get_db().close()
        return jsonify({"status": "healthy"})
    except psycopg2.OperationalError:
        return jsonify({"status": "unhealthy"}), 503
if __name__ == '__main__':
    if not wait_for_db():
        sys.exit(1)
    app.run(host='0.0.0.0', port=5000, debug=False)
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
    echo "--- Building Docker images and starting containers via Docker Compose ---"
    # The DOCKER_COMPOSE_CMD variable will be either "docker compose" or "docker-compose"
    $DOCKER_COMPOSE_CMD build
    $DOCKER_COMPOSE_CMD up -d
    echo ""
    echo "✅ Dockerized application started."
    echo "   View logs with: $DOCKER_COMPOSE_CMD logs -f"
    echo "   Test endpoint: curl http://localhost:8080/api/products"
}

# --- Function to stop Dockerized application ---
stop_docker_app() {
    echo "--- Stopping and removing Docker containers, networks, and volumes ---"
    if [ -f "docker-compose.yml" ]; then
        $DOCKER_COMPOSE_CMD down --volumes
    fi
    clean_docker_files
    echo "✅ Dockerized application stopped."
}

# --- Function to run benchmark ---
run_benchmark() {
    echo "--- Running performance benchmark against Dockerized setup ---"
    if ! command -v ab >/dev/null; then
        echo "ERROR: 'ab' (ApacheBench) not found. Please run 'sudo apt-get install apache2-utils'." >&2
        exit 1
    fi
    echo "Benchmarking http://localhost:8080/api/products ..."
    ab -n 1000 -c 100 http://localhost:8080/api/products
}

# --- Main script logic ---
discover_commands # Ensure Docker/Compose/ab are available

case "$1" in
    start)
        start_docker_app
        ;;
    stop)
        stop_docker_app
        ;;
    benchmark)
        run_benchmark
        ;;
    clean)
        clean_docker_files
        ;;
    *)
        echo "Usage: sudo $0 {start|stop|benchmark|clean}"
        exit 1
        ;;
esac

exit 0
