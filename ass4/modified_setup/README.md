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

## Verifying Round-Robin Load Balancing

The API Gateway is configured to distribute requests to the three `product-service` replicas in a round-robin fashion. You can verify this by sending multiple requests and observing the logs of the service replicas.

1.  **Send multiple requests to the `/api/products` endpoint:**

    You can do this from the host machine using `curl`. The requests will be forwarded through the `nginx-lb` namespace to the `api-gateway`.

    ```bash
    for i in {1..6}; do curl http://172.20.0.10/api/products; echo; done
    ```
    *(Note: You might need to run `sudo apt-get install curl` if you don't have it installed.)*

2.  **Check the logs of the product service replicas:**

    The `assignment4-services.sh` script redirects the output of each service to a log file in the `/tmp` directory. You can `tail` these log files to see which replica served which request.

    Open three separate terminal windows and run the following commands, one in each terminal:

    **Terminal 1:**
    ```bash
    tail -f /tmp/product-service-1.log
    ```

    **Terminal 2:**
    ```bash
    tail -f /tmp/product-service-2.log
    ```

    **Terminal 3:**
    ```bash
    tail -f /tmp/product-service-3.log
    ```

    Now, when you run the `curl` loop from step 1, you will see the log messages appearing in each terminal in a round-robin sequence, confirming that the load balancing is working. Each log entry will show the IP address of the replica that served the request.
