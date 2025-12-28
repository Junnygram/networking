# Bonus 1: Implement a Simple Proxy with Envoy

This directory contains a minimal implementation of a centralized proxy pattern using Docker Compose and Envoy. This is a stepping stone to understanding a full service mesh.

## Components

1.  **`docker-compose.yml`**: Defines three services:
    - `frontend`: A simple `alpine` container that we will use to send a request.
    - `backend`: A standard `nginx` web server.
    - `envoy`: A central Envoy proxy.

2.  **`envoy.yaml`**: A basic configuration for the Envoy proxy. It's configured to:
    - Listen for incoming traffic on port `8000`.
    - Route that traffic to the `backend` service on port `80`.

## How to Run

1.  **Start the services:**
    ```bash
    docker-compose up --build -d
    ```

2.  **Test the connection:**
    Open a terminal and execute a `curl` command from the `frontend` container, but send it to the `envoy` service instead of the `backend`.

    ```bash
    docker-compose exec frontend sh -c "apk add --no-cache curl && curl -v http://envoy:8000"
    ```
    You will see that the `envoy` service receives the request and proxies it to the `backend` service, returning the `nginx` welcome page. This demonstrates how a proxy can decouple service-to-service communication.

## Key Concepts Demonstrated

- **Centralized Proxy:** A single proxy manages traffic routing between other services.
- **Service Discovery:** The Envoy proxy finds the `backend` service using Docker's internal DNS.
- **Decoupling:** The `frontend` does not need to know the direct address or port of the `backend`; it only needs to know about the proxy. This makes it easier to change or replace backend services without reconfiguring the frontend.