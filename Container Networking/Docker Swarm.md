# Docker Swarm

> Scaling from single-host [[Docker and Docker Compose]] to a multi-node cluster with [[overlay network]]s, service replicas, and the ingress routing mesh.
>
> Part of [[Container Networking]] · Builds on [[Docker and Docker Compose]]

---

## Why Swarm?

Single-host [[Docker Compose]] has a fundamental limitation: everything runs on **one machine**. If that machine goes down, everything goes down. [[Docker Swarm]] solves this with:

- **Multi-host clusters** — services spread across machines
- **[[overlay network]]s** — containers on different hosts communicate via [[VXLAN]]
- **Automatic load balancing** — the ingress mesh routes traffic to the right container
- **Self-healing** — if a container dies, Swarm restarts it; if a node dies, tasks are rescheduled

---

## Core Concepts

| Concept | What it does |
|---------|-------------|
| **Manager node** | Runs the control plane — scheduling, state, Raft consensus |
| **Worker node** | Executes containers (tasks) assigned by the manager |
| **Service** | Declarative desired state — image, replicas, networks |
| **Task** | A single container instance running as part of a service |
| **Overlay network** | Cross-host networking using [[VXLAN]] |
| **Ingress mesh** | Routes external requests to any node → forwarded to the right container |

---

## Setting Up the Cluster

### Initialize the manager

```bash
# On the manager node
docker swarm init --advertise-addr <MANAGER_PRIVATE_IP>

# Outputs a join command with a token — save it!
```

### Join worker nodes

```bash
# On each worker — paste the join command from the manager
docker swarm join --token SWMTKN-xxx <MANAGER_IP>:2377
```

### Verify the cluster

```bash
# On the manager
docker node ls
# Shows all nodes, their roles, and status
```

### Required firewall ports

| Port | Protocol | Purpose |
|------|----------|---------|
| 2377 | TCP | Cluster management |
| 7946 | TCP/UDP | Node-to-node communication |
| 4789 | UDP | [[VXLAN]] overlay traffic |

> [!important]
> If using [[AWS]], add these ports to your Security Group. The easiest approach: allow all traffic between instances in the same security group.

---

## Deploying a Stack

Create a Compose file with overlay networks and deploy it as a stack:

```yaml
version: '3.8'

services:
  nginx-lb:
    image: nginx:alpine
    ports:
      - "8080:80"
    networks:
      - frontend_net
    deploy:
      replicas: 1

  api-gateway:
    image: myregistry/api-gateway:1.0
    networks:
      - frontend_net
      - backend_net
    deploy:
      replicas: 2

  product-service:
    image: myregistry/product-service:1.0
    networks:
      - backend_net
      - cache_net
    deploy:
      replicas: 3

  order-service:
    image: myregistry/order-service:1.0
    networks:
      - backend_net
      - database_net
    deploy:
      replicas: 2

  redis-cache:
    image: redis:7-alpine
    networks:
      - cache_net
    deploy:
      replicas: 1

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
    deploy:
      replicas: 1
      placement:
        constraints:
          - node.role == manager

networks:
  frontend_net:
    driver: overlay
  backend_net:
    driver: overlay
  cache_net:
    driver: overlay
  database_net:
    driver: overlay

volumes:
  pgdata:
```

> [!note] Key differences from [[Docker Compose]]
> - Networks use `driver: overlay` instead of `bridge` — they work across hosts
> - Images must be **pre-built and in a registry** (Docker Hub, [[AWS ECR]])
> - The `deploy:` section defines replicas, placement constraints, and resources
> - Port 8080 is accessible on **ANY node** via the ingress routing mesh

### Deploy and manage

```bash
# Deploy
docker stack deploy -c docker-compose.yml myapp

# Check services
docker service ls

# Check individual containers (tasks)
docker service ps myapp_product-service

# View logs
docker service logs -f myapp_api-gateway

# Scale a service
docker service scale myapp_product-service=5

# Remove the stack
docker stack rm myapp

# Leave swarm mode
docker swarm leave --force
```

---

## How Overlay Networks Work

Swarm creates [[VXLAN]] tunnels automatically between nodes:

```
Host A (Manager)                    Host B (Worker)
┌──────────┐                        ┌──────────┐
│ api-gw   │                        │ product  │
│ 10.0.1.5 │                        │ 10.0.1.8 │
└────┬─────┘                        └────┬─────┘
     │                                   │
┌────┴──────────┐                  ┌─────┴─────────┐
│ VXLAN tunnel  │ ═══UDP:4789═══>  │ VXLAN tunnel   │
│ (encapsulate) │                  │ (decapsulate)  │
└───────────────┘                  └────────────────┘
```

Containers on different physical hosts communicate as if they're on the same local network. Swarm handles all the encapsulation and routing.

---

## The Ingress Routing Mesh

Even if `nginx-lb` is only running on the manager, port 8080 is reachable on **every node** in the cluster:

```
User → Worker-2:8080 → (ingress mesh) → Manager:nginx-lb container
```

This means any node can receive traffic and route it to the correct container, regardless of where it's running.

---

## Operations and Troubleshooting

### Common issues

| Problem | Diagnosis | Fix |
|---------|-----------|-----|
| `0/3` replicas running | `docker service ps myapp_<svc>` — check ERROR | Fix image name or resource limits |
| Cross-host communication fails | Check firewall: 2377, 7946, 4789 | Open the required Swarm ports |
| Endpoint not responding | Check if container and port are healthy | Inspect logs and service status |
| Container keeps restarting | `docker service logs myapp_<svc>` | Fix the application crash |

### Monitoring

```bash
# Real-time resource usage
docker stats

# Service overview
docker service ls

# Detailed inspection
docker service inspect myapp_api-gateway --pretty

# Node status
docker node ls
```

---

## Next Steps

[[Docker Swarm]] solves multi-host deployment but has limitations compared to [[Kubernetes]]:
- No native auto-scaling
- Limited scheduling control (no affinity, taints)
- No built-in storage orchestration

Move to [[Kubernetes Networking and Scheduling]] for the industry-standard orchestrator.

---

#docker #docker-swarm #overlay-networks #container-networking #clustering #vxlan
