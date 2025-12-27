# Project Implementation Guide

## 1. Introduction

This guide provides a comprehensive, step-by-step walkthrough for deploying the e-commerce application. It covers two major phases of the project's evolution:

1.  **Phase 1: Manual Deployment with Linux Primitives.** This phase demonstrates how to build the entire infrastructure from the ground up using fundamental Linux tools like network namespaces, bridges, and `iptables`. This is essential for understanding the underlying mechanics of container networking.
2.  **Phase 2: Automated Deployment with Docker Swarm.** This phase shows how to deploy the application in its final, production-ready state as a multi-host, scalable, and resilient cluster using Docker Swarm.

It is recommended to follow the phases in order to fully appreciate the evolution and the advantages provided by modern container orchestrators.

---

## Phase 1: Manual Deployment with Linux Primitives

This phase recreates the advanced, segmented network from Assignment 4, which is the culmination of the manual setup process.

### Step 1.1: Prerequisites

Ensure your Linux host has the necessary tools. For Debian/Ubuntu:
```bash
sudo apt-get update
sudo apt-get install -y iproute2 nginx redis-tools python3 python3-pip postgresql-client postgresql
```

### Step 1.2: Set Up the Segmented Network

This step creates the three isolated network bridges (`br-frontend`, `br-backend`, `br-database`) and the required network namespaces.

1.  Navigate to the `ass4/modified_setup/` directory.
2.  Execute the network setup script. This script is idempotent and will clean up any previous resources before running.

```bash
cd ass4/modified_setup/
sudo ./assignment4-network.sh
```

This will create the complete network topology, including the multi-homed `api-gateway` namespace.

<!-- Image Placeholder: Output of assignment4-network.sh script -->

### Step 1.3: Deploy the Application Services

This step deploys the application source code and starts the services in their respective namespaces.

1.  From the same `ass4/modified_setup/` directory, run the services script:

```bash
sudo ./assignment4-services.sh start
```

This script will:
*   Create a Python virtual environment.
*   Generate the necessary application source files (`api-gateway-lb.py`, etc.).
*   Start all services in the background within their correct namespaces.

<!-- Image Placeholder: Output of assignment4-services.sh start -->

### Step 1.4: Verify the Manual Deployment

1.  **Check Service Status:**
    ```bash
    sudo ./assignment4-services.sh status
    ```
    This should show all services running.

2.  **Test the Endpoint:**
    From the host, use `curl` to make a request to the Nginx load balancer. Since port forwarding was not implemented in the final manual scripts, you must `exec` into the `nginx-lb` namespace to test.

    ```bash
    sudo ip netns exec nginx-lb curl http://172.20.0.20:3000/api/products
    ```
    You should see a JSON response with the product list. Repeatedly running this command should ideally show the `served_by` IP address changing, demonstrating the round-robin load balancer in the API gateway.

### Step 1.5: Tear Down the Manual Deployment

To clean up the environment, run the `stop` and `cleanup` commands.

```bash
sudo ./assignment4-services.sh stop
sudo ./assignment4-network.sh cleanup
```

---

## Phase 2: Automated Deployment with Docker Swarm

This phase deploys the application in its final, most advanced state on a multi-host Docker Swarm cluster. This requires at least two hosts (one manager, one worker).

### Step 2.1: Prerequisites (On All Hosts)

1.  **Install Docker:** Docker must be installed on all hosts that will be part of the Swarm. The `host-b-worker.sh` script can do this automatically on the worker, but it's best to ensure it's done beforehand. Follow the official Docker installation guide for your OS.

2.  **User Permissions:** Add your user to the `docker` group to run Docker commands without `sudo`.
    ```bash
    sudo usermod -aG docker $USER
    ```
    **Crucially, you must start a new shell session after this for the change to take effect (`newgrp docker` or log out and log back in).**

3.  **Firewall Configuration:** Ensure your hosts can communicate with each other over the necessary ports for Swarm (TCP 2377, TCP/UDP 7946, UDP 4789). On cloud platforms, this usually means configuring the security group to allow inbound traffic from other members of the same group.

### Step 2.2: Initialize the Swarm Cluster

1.  **On the Manager Host:**
    *   Navigate to the `ass6/` directory.
    *   Run the manager setup script, providing the host's private IP address.
    ```bash
    cd ass6/
    ./host-a-manager.sh init <MANAGER_HOST_IP>
    ```
    *   The script will initialize the Swarm and print a `docker swarm join ...` command. **Copy this entire command.**

    <!-- Image Placeholder: Output of Swarm init command -->

2.  **On the Worker Host:**
    *   Navigate to the `ass6/` directory.
    *   Run the worker setup script.
    ```bash
    cd ass6/
    ./host-b-worker.sh join
    ```
    *   When prompted, **paste the `docker swarm join` command** you copied from the manager. The worker will connect to the cluster.

3.  **Verify the Cluster (On Manager Host):**
    ```bash
    docker node ls
    ```
    You should see both the manager and worker nodes listed with a status of `Ready`.

### Step 2.3: Deploy the Application Stack

This process is performed entirely on the **manager node**.

1.  **Use the `manager.sh` script for lifecycle management:**
    This script is the simplified "development" workflow that builds images locally.

    *   First, generate the application source code:
        ```bash
        ./manager.sh outputfile
        ```

    *   Next, build the Docker images from the source code:
        ```bash
        ./manager.sh build
        ```

    *   Finally, deploy the stack to the Swarm:
        ```bash
        ./manager.sh deploy
        ```
        This command uses the `docker stack deploy` command with a here-document to deploy a simplified, two-service version of the application, with both services constrained to run on the manager node.

2.  **Use the `docker-compose.yml` for the full deployment:**
    This is the definitive "production" workflow.
    * Make sure you have the `docker-compose.yml` file in the `ass6` directory.
    * Run the deploy command from `host-a-manager.sh`
    ```bash
    ./host-a-manager.sh deploy
    ```
    This command uses `docker stack deploy` to deploy the full, six-service application stack as defined in the `docker-compose.yml` file. Docker Swarm will distribute the service replicas across both the manager and worker nodes.

### Step 2.4: Verify the Swarm Deployment

1.  **Check Service Status (On Manager Host):**
    ```bash
    docker service ls
    ```
    You should see all services (`myapp_nginx-lb`, `myapp_api-gateway`, etc.) listed with the desired number of replicas running.

    <!-- Image Placeholder: Output of `docker service ls` -->

2.  **Test the Endpoint:**
    The Nginx service is published on port `8080` across the Swarm's ingress mesh. You can send a request to this port on *either* the manager's or the worker's public IP address.
    ```bash
    curl http://<MANAGER_OR_WORKER_IP>:8080/api/products
    ```
    You should receive a successful JSON response.

### Step 2.5: Tear Down the Swarm Deployment

1.  **Remove the Application Stack (On Manager Host):**
    ```bash
    # Using the manager.sh script
    ./manager.sh clean

    # Or to remove the full stack
    docker stack rm myapp
    ```

2.  **Disband the Cluster:**
    *   On the worker host(s): `docker swarm leave`
    *   On the manager host: `docker swarm leave --force`
