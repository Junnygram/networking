#!/bin/bash
# ===================================================================================
# FINAL MANAGER SCRIPT (v8.0)
#
# This script manages the application lifecycle with distinct commands.
#
# Workflow:
# 1. ./manager.sh outputfile
# 2. ./manager.sh build
# 3. ./manager.sh deploy
#
# To remove:
# ./manager.sh clean
# ===================================================================================

set -e

# --- Helper Functions ---
check_docker_permissions() {
    if ! docker info > /dev/null 2>&1; then
        echo "❌ ERROR: Your user ('$USER') cannot connect to the Docker daemon."
        echo "This is likely because you have just been added to the 'docker' group."
        echo ""
        echo "💡 Please run 'newgrp docker' or log out and log back in to apply the change."
        exit 1
    fi
    # Docker daemon might not be running if permissions are fine but Docker was just installed.
    # Attempt to start if it's not running
    if ! docker info > /dev/null 2>&1; then
        echo "💡 Docker daemon not running. Attempting to start it..."
        sudo systemctl start docker || true
        sleep 2 # Give it a moment to start
        if ! docker info > /dev/null 2>&1; then
             echo "❌ Failed to start Docker daemon. Please investigate."
             exit 1
        fi
    fi
    echo "✅ Docker permissions are correct and daemon is running."
}

install_docker() {
    if command -v docker >/dev/null; then
        echo "✅ Docker is already installed."
    else
        echo "--- Installing Docker Engine ---"
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        echo "✅ Docker installation complete."
    fi
    sudo groupadd docker || true # Ensure docker group exists
    sudo usermod -aG docker "$USER"
    echo "✅ User '$USER' added to 'docker' group (if not already)."
    echo "IMPORTANT: If you just installed Docker or added yourself to the group, you MAY need to run 'newgrp docker' or log out/in."
}

# This function generates all the necessary source files
outputfile() {
    echo "--- Generating source files... ---"

    # Create api-gateway.py
    cat << 'EOF' > api-gateway.py
from flask import Flask, jsonify, request
import requests
import os

app = Flask(__name__)
PRODUCT_SERVICE_URL = "http://product-service:5000"

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "service": "api-gateway"})

@app.route('/api/products', methods=['GET'])
def get_products():
    try:
        response = requests.get(f"{PRODUCT_SERVICE_URL}/products")
        response.raise_for_status()
        return jsonify(response.json()), response.status_code
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Product service unavailable: {str(e)}"}), 503
        
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000)
EOF
    echo "✅ Created api-gateway.py"

    # Create Dockerfile.api-gateway
    cat << 'EOF' > Dockerfile.api-gateway
FROM python:3.11-slim
WORKDIR /app
COPY requirements-api-gateway.txt .
RUN pip install --no-cache-dir -r requirements-api-gateway.txt
COPY api-gateway.py .
EXPOSE 3000
CMD ["python", "api-gateway.py"]
EOF
    echo "✅ Created Dockerfile.api-gateway"

    # Create requirements-api-gateway.txt
    cat << 'EOF' > requirements-api-gateway.txt
Flask==2.3.2
requests==2.31.0
EOF
    echo "✅ Created requirements-api-gateway.txt"

    # Create product-service.py
    cat << 'EOF' > product-service.py
from flask import Flask, jsonify
import os

app = Flask(__name__)

PRODUCTS = {
    "1": {"id": "1", "name": "Cloud Laptop", "price": 1299.99},
    "2": {"id": "2", "name": "Container Mouse", "price": 39.99},
    "3": {"id": "3", "name": "Serverless Keyboard", "price": 89.99},
}

@app.route('/products', methods=['GET'])
def get_products():
    return jsonify(list(PRODUCTS.values()))

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF
    echo "✅ Created product-service.py"

    # Create Dockerfile.product-service
    cat << 'EOF' > Dockerfile.product-service
FROM python:3.11-slim
WORKDIR /app
COPY requirements-product-service.txt .
RUN pip install --no-cache-dir -r requirements-product-service.txt
COPY product-service.py .
EXPOSE 5000
CMD ["python", "product-service.py"]
EOF
    echo "✅ Created Dockerfile.product-service"

    # Create requirements-product-service.txt
    cat << 'EOF' > requirements-product-service.txt
Flask==2.3.2
EOF
    echo "✅ Created requirements-product-service.txt"
}

# This function builds the images locally
build() {
    echo "--- Building local Docker images... ---"
    if [ ! -f "Dockerfile.api-gateway" ]; then
        echo "❌ Source files not found. Please run './manager.sh outputfile' first."
        exit 1
    fi
    docker build -t api-gateway:local -f Dockerfile.api-gateway .
    docker build -t product-service:local -f Dockerfile.product-service .
    echo "✅ Local images built."
}

# This function deploys the stack using the pre-built local images
deploy() {
    echo "--- Deploying application stack 'myapp' ---"
    # Verify images exist
    if ! docker image inspect api-gateway:local > /dev/null 2>&1; then
        echo "❌ 'api-gateway:local' image not found. Please run './manager.sh build' first."
        exit 1
    fi
    if ! docker image inspect product-service:local > /dev/null 2>&1; then
        echo "❌ 'product-service:local' image not found. Please run './manager.sh build' first."
        exit 1
    fi

    docker stack deploy -c - myapp << 'EOF'
version: '3.8'
services:
  api-gateway:
    image: api-gateway:local
    ports:
      - "8080:3000"
    networks:
      - app_net
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
  product-service:
    image: product-service:local
    networks:
      - app_net
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
networks:
  app_net:
    driver: overlay
EOF

    echo "✅ Stack 'myapp' deployed. All services are running on the manager node."
}

# This function removes the stack
clean() {
    echo "--- Removing application stack 'myapp' ---"
    docker stack rm myapp || echo "Stack 'myapp' not found or already removed."
    echo "✅ Stack cleanup complete."
}


# --- Main script logic ---
CMD=$1

install_docker
check_docker_permissions

case "$CMD" in
    outputfile) outputfile;;
    build) build;;
    deploy) deploy;;
    clean) clean;;
    *)
        echo "Usage: $0 {outputfile|build|deploy|clean}" >&2
        exit 1
        ;;
esac

exit 0