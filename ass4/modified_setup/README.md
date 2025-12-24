# Assignment 4: Modified Setup (Network Segmentation & Load Balancing)

This directory contains a new set of scripts that build a more advanced and realistic network architecture, as described in Part B of Assignment 4.

## Key Architectural Changes

1.  **Network Segmentation**: Instead of one single bridge (`br0`), this setup creates three separate bridges to isolate different parts of the application:
    *   `br-frontend`: For public-facing services (Nginx, API Gateway). Subnet: `172.20.0.0/24`.
    *   `br-backend`: For internal application services (API Gateway, Product Service, Order Service). Subnet: `172.21.0.0/24`.
    *   `br-database`: For data stores (Redis, PostgreSQL). Subnet: `172.22.0.0/24`.

2.  **Multi-Homed API Gateway**: The `api-gateway` namespace is now connected to *both* the frontend and backend bridges, allowing it to receive traffic from Nginx and forward it to the internal services.

3.  **Load Balancing**: The `product-service` now runs in multiple instances (replicas) to handle more load. The API Gateway is updated to distribute traffic between these instances in a round-robin fashion.

## How to Use

1.  **Run the Network Script**:
    This script builds the new, segmented network.
    ```bash
    sudo ./assignment4-network.sh
    ```

2.  **Run the Services Script**:
    This script creates the application files (including the new load-balancing API gateway) and starts all the services in their correct namespaces.
    ```bash
    sudo ./assignment4-services.sh start
    ```

3.  **To Stop and Clean Up**:
    First, stop the services, then tear down the network.
    ```bash
    sudo ./assignment4-services.sh stop
    sudo ./assignment4-network.sh cleanup
    ```
