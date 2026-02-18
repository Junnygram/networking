# Container Networking

> How containers talk to each other — and the world — using [[Linux]] kernel primitives, [[Docker]], and [[Kubernetes]].

---

## The Journey

Container networking is built in layers. Each layer builds on the previous one:

```
                        ┌──────────────────────┐
                        │    Deployment &       │
                        │    Observability      │
                        │  (Helm, CI/CD, Mesh)  │
                        └──────────┬───────────┘
                        ┌──────────┴───────────┐
                        │    Kubernetes         │
                        │ (Scheduling, Storage, │
                        │  Services, Ingress)   │
                        └──────────┬───────────┘
                        ┌──────────┴───────────┐
                        │    Docker Swarm       │
                        │  (Multi-host cluster, │
                        │   Overlay networks)   │
                        └──────────┬───────────┘
                        ┌──────────┴───────────┐
                        │  Docker & Compose     │
                        │ (Containers, DNS,     │
                        │  Health checks)       │
                        └──────────┬───────────┘
                        ┌──────────┴───────────┐
                        │  Linux Primitives     │
                        │ (Namespaces, veth,    │
                        │  Bridge, NAT)         │
                        └──────────────────────┘
```

---

## Notes in This Collection

### Foundations
- [[Linux Network Primitives]] — The kernel technologies powering every container network: [[Network Namespace]]s, [[veth pair]]s, [[Linux Bridge]]s, [[NAT]], [[iptables]], and [[VXLAN]]
- [[Building a Container Network]] — Step-by-step guide to creating a full multi-service network from scratch using only [[Linux]] commands

### Orchestration
- [[Docker and Docker Compose]] — How [[Docker]] automates everything from Part 1, plus [[Docker Compose]] patterns for multi-service stacks
- [[Docker Swarm]] — Scaling to multi-host clusters with [[overlay network]]s, service replicas, and the ingress routing mesh

### Kubernetes
- [[Kubernetes Networking and Scheduling]] — Pod scheduling with [[Node Affinity]], [[Taints and Tolerations]], [[PriorityClass]], [[Static Pods]], and service types
- [[Kubernetes Storage]] — [[PersistentVolume]]s, [[PersistentVolumeClaim]]s, [[StorageClass]]es, [[StatefulSet]]s, and production storage with [[Rook]]-[[Ceph]]
- [[Deployment Strategies]] — [[Canary deployment]], [[Blue-Green deployment]], [[Rolling Update]]s, and [[Helm]] charts

### Advanced
- [[Advanced Container Topics]] — Service mesh with [[Envoy]], distributed tracing with [[Jaeger]], chaos engineering, auto-scaling, and CI/CD pipelines

---

## Core Architecture

Every container network — from a simple `docker run` to a production [[Kubernetes]] cluster — is built on the same foundation:

```
   Container A          Container B
   ┌─────────┐          ┌─────────┐
   │  eth0   │          │  eth0   │
   └────┬────┘          └────┬────┘
        │ veth pair          │ veth pair
   ┌────┴────┐          ┌────┴────┐
   │ veth-a  │          │ veth-b  │
   └────┬────┘          └────┬────┘
        │                    │
   ┌────┴────────────────────┴────┐
   │         Linux Bridge          │
   │        (virtual switch)       │
   └──────────────┬───────────────┘
                  │
             Host eth0 → Internet (via NAT)
```

The building blocks:
1. **[[Network Namespace]]** — isolated network stack per container
2. **[[veth pair]]** — virtual cable connecting namespaces
3. **[[Linux Bridge]]** — virtual switch connecting veth pairs
4. **[[NAT]]** / [[iptables]] — internet access and traffic control
5. **[[DNS]]** — service discovery by name

---

## Key Principles

1. **Every [[Docker]] network is [[Linux]] kernel primitives** — [[Network Namespace]]s, [[veth pair]]s, [[Linux Bridge]]s, [[iptables]]
2. **Understanding the foundation makes debugging intuitive** — [[tcpdump]] on a bridge reveals exactly what containers see
3. **Orchestrators automate what you can do manually** — [[Docker Swarm]] and [[Kubernetes]] manage the same primitives at scale
4. **Network segmentation is [[defense in depth]]** — topology-enforced isolation beats [[iptables]] rules alone
5. **Declarative > imperative** — [[Docker Compose]], [[Kubernetes]] manifests, [[Terraform]], and [[Helm]] make infrastructure reproducible
6. **The best way to learn infrastructure is to build it from scratch** — then appreciate the abstractions

---

#container-networking #linux #docker #kubernetes #devops #MOC
