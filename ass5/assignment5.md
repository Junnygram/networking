# Assignment 5: Docker Migration and Optimization

This assignment focuses on migrating the application infrastructure from pure Linux primitives to a Docker-based setup. You will containerize each service, orchestrate them using Docker Compose, and perform basic performance comparisons.

---

## ⚠️ Step 0: Prerequisites

**1. Docker Engine and Docker Compose (REQUIRED BEFORE RUNNING SCRIPT):**
Ensure Docker Engine and Docker Compose are installed on your host machine.
**Refer to `prerequisite.md` in the project root for detailed installation instructions.**

```bash
# Verify Docker installation (after following prerequisite.md instructions)
docker run hello-world
```

**2. Python Packages:**
Ensure `ab` (ApacheBench) is installed for benchmarking.

```bash
sudo apt-get update
sudo apt-get install -y apache2-utils # Provides 'ab' command
```

**3. Running Environment:**
*   **Important:** This assignment uses Docker's own networking. You should **stop any running services from Assignment 2 and tear down the network from Assignment 1 (or Assignment 4 Modified Setup)** before starting this assignment to avoid port conflicts.
    *   `sudo ./assignment2.sh stop`
    *   `sudo ./assignment1.sh cleanup`
    *   If you ran the `modified_setup` from Assignment 4:
        *   `sudo ./ass4/modified_setup/assignment4-services.sh stop`
        *   `sudo ./ass4/modified_setup/assignment4-network.sh cleanup`

---

## Task 5.1: Containerize All Services

Each service in our microservices architecture will be containerized using a `Dockerfile`. This defines the environment and dependencies for each service.

**1. `Dockerfile.nginx-lb`**

```dockerfile
FROM nginx:alpine

WORKDIR /etc/nginx/conf.d

# Copy the custom nginx.conf
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

**2. `Dockerfile.api-gateway`**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY api-gateway.py .

EXPOSE 3000

CMD ["python", "api-gateway.py"]
```
*Note: You would need to create a `requirements.txt` file containing `Flask`, `requests`.*

**3. `Dockerfile.product-service`**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY product-service.py .

EXPOSE 5000

CMD ["python", "product-service.py"]
```
*Note: You would need to create a `requirements.txt` file containing `Flask`, `redis`.*

**4. `Dockerfile.order-service`**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code
COPY order-service.py .

EXPOSE 5000

CMD ["python", "order-service.py"]
```
*Note: You would need to create a `requirements.txt` file containing `Flask`, `psycopg2-binary`.*

---

## Task 5.2: Docker Compose Setup

Docker Compose allows us to define and run multi-container Docker applications. We will define all our services, their networks, and dependencies in a single `docker-compose.yml` file.

**1. `docker-compose.yml`**

```yaml
version: '3.8'

services:
  nginx-lb:
    build:
      context: .
      dockerfile: Dockerfile.nginx-lb
    ports:
      - "8080:80" # Map host port 8080 to container port 80
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
    # Deploy multiple replicas for load balancing (e.g., 3 instances)
    deploy:
      replicas: 3
    environment:
      # Pass Redis host to product service
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
      # Pass PostgreSQL connection details
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
      - postgres_data:/var/lib/postgresql/data # Persistent storage for DB
    networks:
      - database_net

# Define custom networks for segmentation (similar to Linux bridge setup)
networks:
  frontend_net:
    driver: bridge
  backend_net:
    driver: bridge
  cache_net:
    driver: bridge
  database_net:
    driver: bridge

# Define named volumes for persistent data
volumes:
  postgres_data:
```

---

## Task 5.3: Performance Comparison

Benchmark the Linux primitive implementation (from Assignment 2 or 4) against the new Docker Compose implementation.

**1. Ensure the target application is running:**
*   To benchmark the Linux primitive setup, ensure `sudo ./assignment2.sh start` (or `sudo ./ass4/modified_setup/assignment4-services.sh start`) is running, and the host's port 8080 is forwarded to the Nginx LB.
*   To benchmark the Docker setup, ensure `docker compose up -d` is running.

**2. Run the benchmark:**

```bash
# Example benchmark command for either setup
ab -n 1000 -c 100 http://localhost:8080/api/products
```

**Deliverable:** A report comparing Requests Per Second (RPS) and latency between the two implementations.

---

## Task 5.4: Optimize Docker Setup

Optimizing your Docker setup can lead to smaller images, faster builds, and better runtime performance.

**Optimization Techniques:**
*   **Multi-stage builds**: Use multiple `FROM` instructions to separate build-time dependencies from runtime dependencies, resulting in smaller final images.
*   **Minimize image size**:
    *   Use smaller base images (e.g., `alpine` variants).
    *   Clean up cache and temporary files after installation (`RUN rm -rf /var/cache/apk/*`).
    *   Combine `RUN` commands to reduce layers.
*   **Leverage build cache**: Order instructions from least to most frequently changing.
*   **Health checks**: Add `HEALTHCHECK` instructions to `Dockerfiles` so orchestrators (like Docker Compose) can monitor container health.
*   **Resource limits**: Define `deploy: resources:` in `docker-compose.yml` to limit CPU/memory usage.

**Deliverable:** Optimized Dockerfiles and `docker-compose.yml` with documentation of changes and their benefits.
