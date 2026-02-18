# Advanced Container Topics

> Service mesh with [[Envoy]], distributed tracing with [[Jaeger]], chaos engineering, auto-scaling, and CI/CD pipelines.
>
> Part of [[Container Networking]] · Builds on all previous notes

---

## Service Mesh with [[Envoy]]

A service mesh adds a **proxy layer** between services. Instead of services calling each other directly, all traffic flows through [[Envoy]]:

```
Frontend → Envoy Proxy (port 8000) → Backend (port 80)
```

### Why use a proxy?

| Benefit | Without Mesh | With Mesh |
|---------|-------------|-----------|
| **Service Discovery** | Hardcode IPs or build a registry | Proxy resolves via [[Docker]] DNS |
| **Observability** | Instrument every service | All traffic passes through one point |
| **Traffic Control** | Application-level code | Rate limiting, retries, circuit breaking |
| **Security** | Manual mTLS setup | Automatic encryption between services |

### Setting it up

```yaml
# docker-compose.yml with Envoy as central proxy
services:
  frontend:
    image: alpine
    networks:
      - mesh

  backend:
    image: nginx
    networks:
      - mesh

  envoy:
    image: envoyproxy/envoy:v1.28-latest
    ports:
      - "8000:8000"
      - "8001:8001"    # Admin interface
    volumes:
      - ./envoy.yaml:/etc/envoy/envoy.yaml
    networks:
      - mesh

networks:
  mesh:
    driver: bridge
```

```yaml
# envoy.yaml — route /api/* to backend
static_resources:
  listeners:
    - address:
        socket_address:
          address: 0.0.0.0
          port_value: 8000
      filter_chains:
        - filters:
            - name: envoy.filters.network.http_connection_manager
              typed_config:
                "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
                stat_prefix: ingress
                route_config:
                  virtual_hosts:
                    - name: backend
                      domains: ["*"]
                      routes:
                        - match:
                            prefix: "/"
                          route:
                            cluster: backend_cluster
  clusters:
    - name: backend_cluster
      type: STRICT_DNS
      load_assignment:
        cluster_name: backend_cluster
        endpoints:
          - lb_endpoints:
              - endpoint:
                  address:
                    socket_address:
                      address: backend    # Docker DNS resolves this
                      port_value: 80
```

### Testing

```bash
# Start everything
docker compose up -d

# Traffic flows: frontend → Envoy → backend
docker exec frontend wget -qO- http://envoy:8000/

# View Envoy admin stats
curl http://localhost:8001/stats
```

This pattern is the foundation of full service meshes like [[Istio]] and [[Linkerd]].

---

## Distributed Tracing with [[Jaeger]] & [[OpenTelemetry]]

When a request crosses multiple services, you need to **trace its path** to debug latency and failures.

### Key concepts

| Concept | What it means |
|---------|-------------|
| **Trace** | The full lifecycle of a request across all services |
| **Span** | A single operation within a trace |
| **Context Propagation** | Trace IDs flow automatically in HTTP headers |

### Architecture

```
Your App (instrumented) → OpenTelemetry SDK → Jaeger Collector → Jaeger UI
```

### Instrumenting a [[Flask]] app

```python
from flask import Flask
from opentelemetry import trace
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.jaeger.thrift import JaegerExporter

# Configure tracing
trace.set_tracer_provider(TracerProvider())
jaeger_exporter = JaegerExporter(
    agent_host_name="jaeger",
    agent_port=6831,
)
trace.get_tracer_provider().add_span_processor(
    BatchSpanProcessor(jaeger_exporter)
)

app = Flask(__name__)
FlaskInstrumentor().instrument_app(app)
tracer = trace.get_tracer(__name__)

@app.route('/api/data')
def get_data():
    with tracer.start_as_current_span("fetch-data"):
        # Business logic — automatically traced
        result = process_data()
        return {"data": result}

@app.route('/api/chain')
def chain():
    with tracer.start_as_current_span("chain-request"):
        # Calls to other services propagate the trace context
        import requests
        response = requests.get("http://service-b:5001/api/process")
        return response.json()
```

### [[Jaeger]] UI

Access at `http://localhost:16686` to:
- Search traces by service, operation, or duration
- View the full request waterfall across services
- Identify slow spans and bottlenecks
- Compare traces before/after changes

---

## Chaos Engineering

Intentionally inject failures to test system resilience and self-healing.

### Latency injection

```bash
# Add 200ms delay to a container's network
CONTAINER_ID=$(docker ps -q --filter "name=api-gateway" | head -1)
docker exec $CONTAINER_ID tc qdisc add dev eth0 root netem delay 200ms

# Observe: do health checks catch it? Do clients timeout gracefully?

# Remove latency
docker exec $CONTAINER_ID tc qdisc del dev eth0 root
```

### Container kill

```bash
# Kill a random container
RANDOM_CONTAINER=$(docker ps -q | shuf | head -1)
docker kill $RANDOM_CONTAINER

# Watch: how fast does the orchestrator restart it?
docker service ps myapp_api-gateway  # Swarm
kubectl get pods -w                   # Kubernetes
```

### What to observe and test

| Experiment | What to watch |
|-----------|--------------|
| Kill a service | Does the orchestrator restart it? How fast? |
| Add latency | Do clients timeout? Do health checks fail? |
| Kill a database | Does the app queue writes? Or crash? |
| Network partition | Do services degrade gracefully? |
| Fill disk | Are alerts triggered? Does eviction work? |

### Best practices

- Always run chaos experiments in a **test environment first**
- Define clear **success criteria** before each experiment
- Have a **kill switch** to immediately undo the injection
- Document findings and fix weaknesses before they hit production

---

## Auto-Scaling

### [[Docker Swarm]] — Manual/Simulated

[[Docker Swarm]] doesn't have built-in auto-scaling. You can build a monitoring loop:

```bash
#!/bin/bash
while true; do
    AVG_CPU=$(docker stats --no-stream --format "{{.CPUPerc}}" \
      $(docker ps -q --filter "label=com.docker.swarm.service.name=myapp_api") \
      | sed 's/%//' | awk '{sum+=$1; n++} END {printf "%.0f", sum/n}')

    CURRENT=$(docker service ls --filter "name=myapp_api" --format "{{.Replicas}}" | cut -d'/' -f2)

    if (( AVG_CPU > 70 )) && (( CURRENT < 10 )); then
        NEW=$((CURRENT + 1))
        docker service scale myapp_api=$NEW
        echo "Scaled UP to $NEW (CPU: $AVG_CPU%)"
    elif (( AVG_CPU < 30 )) && (( CURRENT > 2 )); then
        NEW=$((CURRENT - 1))
        docker service scale myapp_api=$NEW
        echo "Scaled DOWN to $NEW (CPU: $AVG_CPU%)"
    fi
    sleep 30
done
```

### [[Kubernetes]] — Built-in HPA

[[Kubernetes]] has native Horizontal Pod Autoscaler:

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

```bash
# Check HPA status
kubectl get hpa

# Generate load to trigger scaling
kubectl run load-gen --image=busybox -- sh -c \
  "while true; do wget -qO- http://api-gateway; done"

# Watch pods scale
kubectl get pods -w
```

---

## CI/CD Pipeline

Automated deployment from code push to production.

### Architecture

```
Code Push → GitHub Actions → Build Docker Images → Push to Registry → Deploy
```

### Infrastructure with [[Terraform]]

```bash
# Terraform provisions:
# - VPC + Subnets + Security Groups
# - EC2 instances with Docker pre-installed
# - ECR repositories for Docker images
# - S3 backend for Terraform state

terraform init
terraform apply -var-file=terraform.tfvars
```

### Application with [[GitHub Actions]]

```yaml
# .github/workflows/deploy.yml
name: Build and Deploy

on:
  push:
    branches: [main]

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      - name: Login to ECR
        run: aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY

      - name: Build and push
        run: |
          docker build -t $ECR_REGISTRY/api-gateway:${{ github.sha }} ./api-gateway
          docker push $ECR_REGISTRY/api-gateway:${{ github.sha }}

      - name: Deploy
        run: |
          ssh -i key.pem ubuntu@$EC2_IP \
            "docker compose pull && docker compose up -d"
```

### Key CI/CD patterns

- **Only rebuild changed services** — detect changes with `git diff`
- **Use immutable, versioned images** — tag with commit SHA, not `latest`
- **Separate infrastructure from application deployment** — [[Terraform]] for infra, [[GitHub Actions]] for app
- **Store secrets properly** — AWS keys, SSH keys in GitHub Secrets
- **Use OIDC** for [[AWS]] authentication instead of long-lived credentials

---

## Next Steps

- Return to [[Container Networking]] for the full picture
- Review [[Linux Network Primitives]] to understand what all these tools abstract away
- See [[Deployment Strategies]] for zero-downtime update patterns

---

#advanced #service-mesh #tracing #chaos-engineering #auto-scaling #ci-cd #container-networking
