# Project Architecture Document

## 1. Introduction

This document outlines the architecture of the containerized e-commerce platform. The architecture is designed to be scalable, resilient, and maintainable, leveraging modern cloud-native principles. The final state of the project is a multi-host deployment orchestrated by Docker Swarm, ensuring high availability and load distribution.

## 2. System Overview

The system is a microservices-based application deployed across a cluster of Docker hosts. It consists of six core services organized into four logical tiers: an edge layer, an application layer, a data layer, and an orchestration layer.

*   **Orchestration Layer:** Docker Swarm is used to manage the cluster, deploy services, and handle networking.
*   **Edge Layer:** An Nginx instance acts as the reverse proxy and single entry point for all external traffic.
*   **Application Layer:** A set of stateless services (`API Gateway`, `Product Service`, `Order Service`) handle the core business logic.
*   **Data Layer:** Stateful services (`Redis`, `PostgreSQL`) provide caching and persistent storage.

<!-- Image Placeholder: High-Level System Architecture Diagram -->

## 3. Service Components

Each component is a containerized service managed by Docker Swarm.

### 3.1. Nginx Load Balancer (`nginx-lb`)
*   **Description:** The primary entry point for all incoming HTTP traffic. It acts as a reverse proxy, forwarding requests to the API Gateway.
*   **Technology:** Nginx
*   **Replicas:** 1 (typically run on a manager node)
*   **Responsibilities:**
    *   Terminating external HTTP traffic on port `8080`.
    *   Forwarding requests to the `api-gateway` service.
    *   Serving as a basic load balancer (though Swarm's ingress mesh provides the primary load balancing).

### 3.2. API Gateway (`api-gateway`)
*   **Description:** A central routing service that directs incoming API requests to the appropriate backend microservice.
*   **Technology:** Python (Flask)
*   **Replicas:** 2+
*   **Responsibilities:**
    *   Receiving requests from Nginx (e.g., `/api/products`, `/api/orders`).
    *   Routing requests to either the `product-service` or the `order-service`.
    *   Distributing load across multiple replicas of the backend services (as implemented in the advanced setup in Assignment 4).

### 3.3. Product Service (`product-service`)
*   **Description:** Manages product information.
*   **Technology:** Python (Flask)
*   **Replicas:** 3+
*   **Responsibilities:**
    *   Providing a list of available products.
    *   Interacting with the Redis cache for faster data retrieval (in more advanced implementations).

### 3.4. Order Service (`order-service`)
*   **Description:** Manages customer orders.
*   **Technology:** Python (Flask)
*   **Replicas:** 2+
*   **Responsibilities:**
    *   Creating new orders.
    *   Persisting order data to the PostgreSQL database.

### 3.5. Redis Cache (`redis-cache`)
*   **Description:** An in-memory data store used for caching.
*   **Technology:** Redis
*   **Replicas:** 1
*   **Responsibilities:**
    *   Storing frequently accessed data (e.g., product lists) to reduce latency and database load.

### 3.6. PostgreSQL Database (`postgres-db`)
*   **Description:** A relational database used for persistent storage.
*   **Technology:** PostgreSQL
*   **Replicas:** 1
*   **Responsibilities:**
    *   Storing all customer order data.
    *   Ensuring data integrity and persistence, using a Docker named volume (`postgres_data`).

## 4. Networking Architecture

The networking is handled by Docker Swarm, using a segmented, multi-host overlay network model. This provides security, organization, and seamless communication across the cluster.

<!-- Image Placeholder: Docker Swarm Overlay Network Diagram -->

### 4.1. Overlay Networks
Four separate `overlay` networks are used to isolate the different application tiers:

*   **`frontend_net`**: Connects external-facing services.
    *   **Services:** `nginx-lb`, `api-gateway`.
    *   **Purpose:** Exposes the API Gateway to the Nginx load balancer.

*   **`backend_net`**: Connects the internal application services.
    *   **Services:** `api-gateway`, `product-service`, `order-service`.
    *   **Purpose:** Allows the API Gateway to communicate with the backend business logic services. This network is not exposed externally.

*   **`cache_net`**: A dedicated network for the caching layer.
    *   **Services:** `product-service`, `redis-cache`.
    *   **Purpose:** Allows the Product Service to connect to Redis.

*   **`database_net`**: A dedicated network for the database layer.
    *   **Services:** `order-service`, `postgres-db`.
    *   **Purpose:** Allows the Order Service to connect to the PostgreSQL database, isolating the database from all other services.

### 4.2. Service Discovery
Docker Swarm provides built-in DNS-based service discovery. Services can reach each other simply by using their service name as a hostname (e.g., the `order-service` connects to the database using the hostname `postgres-db`). Docker's networking stack automatically resolves this name to the correct container IP address, regardless of which host the container is running on.

### 4.3. Ingress Load Balancing
When a port is published (like port `8080` for the `nginx-lb` service), Docker Swarm's **ingress routing mesh** makes that service accessible on the published port on *every node in the swarm*. If a request comes into a node that is not running the service, Swarm automatically routes the request to a node that is. This provides network-level load balancing before the request even reaches Nginx.

## 5. Data Flow

A typical request flows through the system as follows:

1.  A user's request hits port `8080` on any node in the Swarm cluster.
2.  Swarm's ingress routing mesh directs the request to the `nginx-lb` container.
3.  Nginx forwards the HTTP request to the `api-gateway` service over the `frontend_net`. Swarm's internal load balancer distributes the request to one of the `api-gateway` replicas.
4.  The API Gateway inspects the URL. If it's a request for `/api/products`, it forwards the request to the `product-service` over the `backend_net`.
5.  Swarm's internal load balancer distributes the request to one of the `product-service` replicas.
6.  The `product-service` fetches the data and returns it to the API Gateway.
7.  The API Gateway returns the response to Nginx, which sends it back to the user.

<!-- Image Placeholder: Data Flow Diagram for a Product Request -->

## 6. Scalability and High Availability

*   **Scalability:** Stateless services (`api-gateway`, `product-service`, `order-service`) are deployed with multiple replicas. The number of replicas can be increased with a single command (`docker service scale...`) to handle more load.
*   **High Availability:** By running multiple replicas across different hosts, the application can tolerate the failure of a single container or even an entire host. Docker Swarm will automatically reschedule failed containers on healthy nodes.
*   **Stateful Services:** Stateful services (`redis-cache`, `postgres-db`) are run as single replicas with persistent storage backed by a named volume to ensure data is not lost if the container is recreated.
