# Assignment 5: Manual Docker Migration Commands

This document provides the step-by-step commands to manually containerize the application and run it with Docker Compose, as an alternative to the `assignment5.sh` script.

**Prerequisites:**
* Docker and Docker Compose are installed and your user has permission to run them.
* Any environments from previous assignments have been torn down to avoid port conflicts.

---

## 1. Create the Application and Configuration Files

First, create all the necessary source code, configuration, and Docker-related files.

### `requirements.txt`
This file lists the Python dependencies for all services.
```bash
cat << 'EOF' > requirements.txt
Flask
requests
psycopg2-binary
redis
EOF
```

### `nginx.conf`
The Nginx configuration now points to the API gateway using its service name, `api-gateway`, which will be resolved by Docker's internal DNS.
```bash
cat << 'EOF' > nginx.conf
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
```

### Python Application Files
These are the robust versions of the application code, designed to wait for their dependencies.

**`api-gateway.py`**
```bash
cat << 'EOF' > api-gateway.py
from flask import Flask, jsonify, request
import requests, os
app = Flask(__name__)
PRODUCT_SERVICE = os.getenv("PRODUCT_SERVICE_URL", "http://product-service:5000")
@app.route('/health')
def health(): return jsonify({"status": "healthy"})
@app.route('/api/products')
def get_products():
    res = requests.get(f"{PRODUCT_SERVICE}/products")
    return res.content, res.status_code
if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3000, debug=False)
EOF
```

**`product-service.py`**
```bash
cat << 'EOF' > product-service.py
from flask import Flask, jsonify
import redis, os, time, sys
app = Flask(__name__)
def get_redis_connection():
    return redis.Redis(host=os.getenv("REDIS_HOST", "redis-cache"), port=6379, decode_responses=True, socket_connect_timeout=2)
def wait_for_redis():
    retries = 30;
    while retries > 0:
        try:
            get_redis_connection().ping()
            return True
        except redis.exceptions.ConnectionError:
            print(f"Waiting for Redis... ({retries} retries left)", file=sys.stderr)
            retries -= 1; time.sleep(3)
    return False
@app.route('/health')
def health():
    try:
        get_redis_connection().ping(); return jsonify({"status": "healthy"})
    except redis.exceptions.ConnectionError:
        return jsonify({"status": "unhealthy"}), 503
@app.route('/products')
def get_products():
    return jsonify([{"id": "1", "name": "Dockerized Laptop"}])
if __name__ == '__main__':
    if not wait_for_redis(): sys.exit(1)
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF
```

**`order-service.py`**
```bash
cat << 'EOF' > order-service.py
from flask import Flask, jsonify
import psycopg2, os, sys, time
app = Flask(__name__)
def get_db():
    return psycopg2.connect(host=os.getenv("DB_HOST"), dbname=os.getenv("POSTGRES_DB"), user=os.getenv("POSTGRES_USER"), password=os.getenv("POSTGRES_PASSWORD"), connect_timeout=3)
def wait_for_db():
    retries = 30
    while retries > 0:
        try:
            get_db().close(); return True
        except psycopg2.OperationalError:
            print(f"Waiting for DB... ({retries} retries left)", file=sys.stderr)
            retries -= 1; time.sleep(3)
    return False
@app.route('/health')
def health():
    try:
        get_db().close(); return jsonify({"status": "healthy"})
    except psycopg2.OperationalError:
        return jsonify({"status": "unhealthy"}), 503
if __name__ == '__main__':
    if not wait_for_db(): sys.exit(1)
    app.run(host='0.0.0.0', port=5000, debug=False)
EOF
```

## 2. Create Dockerfiles

Create a `Dockerfile` for each service that needs to be built from source.

**`Dockerfile.nginx-lb`**
```bash
cat << 'EOF' > Dockerfile.nginx-lb
FROM nginx:alpine
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
EOF
```

**`Dockerfile.api-gateway`**
```bash
cat << 'EOF' > Dockerfile.api-gateway
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY api-gateway.py .
EXPOSE 3000
CMD ["python", "api-gateway.py"]
EOF
```

**`Dockerfile.product-service`**
```bash
cat << 'EOF' > Dockerfile.product-service
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY product-service.py .
EXPOSE 5000
CMD ["python", "product-service.py"]
EOF
```

**`Dockerfile.order-service`**
```bash
cat << 'EOF' > Dockerfile.order-service
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY order-service.py .
EXPOSE 5000
CMD ["python", "order-service.py"]
EOF
```

## 3. Create the `docker-compose.yml` File

This file defines all the services, networks, and volumes, and orchestrates the entire application. It includes health checks and dependency conditions to ensure a reliable startup order.
```bash
cat << 'EOF' > docker-compose.yml
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
```

## 4. Build and Run the Application

With all the files in place, you can now use Docker Compose to build the images and start the containers.

**Step 1: Build the Docker images**
This command builds the images for the services that have a `build` instruction.
```bash
docker compose build
```

**Step 2: Start the application**
This command starts all services in the background (`-d`).
```bash
docker compose up -d
```

## 5. Verify and Clean Up

**Verify:**
Check that all containers are running and healthy.
```bash
docker compose ps
```
Test the application endpoint.
```bash
curl http://localhost:8080/api/products
```

**Clean Up:**
Stop and remove all containers, networks, and the named volume.
```bash
docker compose down --volumes
```
You can then remove the generated source and Docker files.
