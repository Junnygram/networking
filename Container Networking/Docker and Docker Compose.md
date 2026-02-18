# Docker and Docker Compose

> How [[Docker]] automates [[Linux Network Primitives]] and how [[Docker Compose]] provides declarative multi-service orchestration.
>
> Part of [[Container Networking]] · Builds on [[Building a Container Network]]

---

## What Docker Does Under the Hood

When you run `docker run nginx`, [[Docker]] executes exactly what you did manually in [[Building a Container Network]]:

1. Creates a [[Network Namespace]] for the container
2. Creates a [[veth pair]] — one end in the container, one on the docker bridge (`docker0`)
3. Assigns an IP from the bridge's subnet
4. Sets up [[NAT]] rules via [[iptables]] for internet access
5. Configures [[DNS]] at `127.0.0.11` for user-defined networks

The entire foundation of [[Linux Network Primitives]] — automated into a single command.

---

## Docker Networking Basics

### Creating and using networks

```bash
# Create a custom bridge network
docker network create mynet

# Run containers on it — they can discover each other by name
docker run -d --name api --network mynet flask-app
docker run -d --name web --network mynet nginx

# DNS resolution works automatically
docker exec web curl http://api:5000  # ✅ Docker DNS resolves 'api'

# Inspect the network
docker network inspect mynet
```

> [!important]
> The default `bridge` network does **not** support DNS discovery. Always create a custom network.

### Network modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Bridge** | Private network with [[NAT]] (default) | Most containers |
| **Host** | Shares the host's network directly | Performance-critical apps |
| **None** | No networking | Security-sensitive workloads |
| **Container** | Shares another container's namespace | Sidecar patterns ([[Kubernetes]] pods) |

---

## Docker Compose — Declarative Orchestration

[[Docker Compose]] creates a dedicated bridge network per project and handles all networking automatically.

### Full segmented stack

```yaml
version: '3.8'

services:
  nginx-lb:
    image: nginx:alpine
    ports:
      - "8080:80"
    networks:
      - frontend_net
    depends_on:
      api-gateway:
        condition: service_healthy

  api-gateway:
    build: ./api-gateway
    networks:
      - frontend_net
      - backend_net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/health"]
      interval: 10s
      timeout: 5s
      retries: 3
    depends_on:
      product-service:
        condition: service_healthy
      order-service:
        condition: service_healthy

  product-service:
    build: ./product-service
    networks:
      - backend_net
      - cache_net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000/health"]
      interval: 10s
      timeout: 5s
      retries: 3
    depends_on:
      redis-cache:
        condition: service_healthy

  order-service:
    build: ./order-service
    networks:
      - backend_net
      - database_net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5001/health"]
      interval: 10s
      timeout: 5s
      retries: 3
    depends_on:
      postgres-db:
        condition: service_healthy

  redis-cache:
    image: redis:7-alpine
    networks:
      - cache_net
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      retries: 5

  postgres-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: secret
    networks:
      - database_net
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d orders"]
      interval: 5s
      retries: 5

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
  pgdata:
```

---

## Three Layers of Startup Reliability

Reliable service startup needs **three layers** of defense against race conditions:

### Layer 1: Docker healthcheck

Declares when a service is actually ready (not just "container started"):

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U appuser -d orders"]
  interval: 5s
  retries: 5
```

### Layer 2: depends_on with service_healthy

Compose waits for dependencies to pass their health checks:

```yaml
depends_on:
  postgres-db:
    condition: service_healthy
```

### Layer 3: Application-level retries

Belt-and-suspenders approach in the code itself:

```python
import time
import psycopg2

def wait_for_db(max_retries=30, delay=2):
    """Wait for PostgreSQL to accept connections."""
    for attempt in range(max_retries):
        try:
            conn = psycopg2.connect(
                host="postgres-db",  # Docker DNS resolves this
                database="orders",
                user="appuser",
                password="secret"
            )
            conn.close()
            print("Database is ready!")
            return
        except psycopg2.OperationalError:
            print(f"Waiting for database... ({attempt + 1}/{max_retries})")
            time.sleep(delay)
    raise Exception("Database not available")
```

> [!tip]
> The three layers mean: even if Docker's health check is slow, the app itself retries. Even if the app doesn't retry, Compose holds it until dependencies are healthy.

---

## Service Discovery with Docker DNS

Services reach each other **by name** — no hardcoded IPs:

| From | To | Address Used |
|------|----|------------|
| `nginx-lb` | `api-gateway` | `http://api-gateway:3000` |
| `api-gateway` | `product-service` | `http://product-service:5000` |
| `api-gateway` | `order-service` | `http://order-service:5001` |
| `product-service` | `redis-cache` | `redis-cache:6379` |
| `order-service` | `postgres-db` | `postgres-db:5432` |

Docker's embedded DNS server at `127.0.0.11` handles all resolution within user-defined networks.

---

## Running and Managing

```bash
# Start everything (background)
docker compose up -d

# Check health status
docker compose ps

# View live logs
docker compose logs -f api-gateway

# Scale a service
docker compose up -d --scale product-service=3

# Stop everything
docker compose down

# Stop and remove all data
docker compose down -v
```

---

## Manual Primitives vs Docker — Comparison

| Aspect | Manual ([[Linux Network Primitives]]) | [[Docker]] & Compose |
|--------|--------------------------------------|---------------------|
| **Complexity** | Very high — expert [[Linux]] knowledge | Low — declarative YAML |
| **Scalability** | Manual, slow, not feasible at scale | `--scale product-service=3` |
| **High Availability** | None without custom work | Built-in health checks + restart |
| **Portability** | Tied to host OS | "Build once, run anywhere" |
| **Reproducibility** | Configuration drift inevitable | Guaranteed via Dockerfile + Compose |
| **Security** | Powerful but error-prone [[iptables]] | Secure by default (network isolation) |
| **Service Discovery** | Must build your own | Built-in DNS |
| **Learning Value** | Excellent for deep understanding | Good but hides mechanics |

> [!note]
> The manual approach is invaluable for **learning**. Docker is superior for **production**.

---

## Next Steps

Single-host Docker Compose has a fundamental limit: everything runs on one machine. Move to [[Docker Swarm]] to scale across multiple hosts with automatic failover.

---

#docker #docker-compose #container-networking #networking #dns #health-checks
