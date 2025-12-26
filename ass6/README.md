# Assignment 6: Multi-Host Swarm Deployment

This directory contains the necessary files to deploy the microservices application across a multi-host environment using Docker Swarm.

## Files

- `host-a-manager.sh`: The setup and management script for your main Swarm node (manager).
- `host-b-worker.sh`: The setup and management script for any worker nodes.
- `docker-compose.yml`: The application stack definition. It is configured to use pre-built images from DockerHub.
- `api-gateway.py`, `product-service.py`, etc.: The raw application code (for reference).

---

## Workflow

Follow these steps to get your multi-host cluster running. You will need at least two hosts (one manager, one worker) with IP connectivity between them.

### Step 1: Initialize the Manager Node (Run on Host A)

First, prepare the manager node. This will install Docker (if needed) and initialize the Swarm.

```bash
# Make the script executable
chmod +x ./host-a-manager.sh

# Run the init command, providing the IP address of this host
# This IP will be advertised to other nodes. Use a private IP if on a cloud provider.
./host-a-manager.sh init <IP_OF_HOST_A>
```

After running this command, it will print a `docker swarm join ...` command. **Copy this command.** You will need it for the worker nodes.

*Note: The script adds your user to the `docker` group. You may need to run `newgrp docker` or log out and back in for the change to apply.*

### Step 2: Initialize and Join the Worker Node(s) (Run on Host B, C, etc.)

Next, prepare each worker node and have it join the swarm.

```bash
# Make the script executable
chmod +x ./host-b-worker.sh

# Run the init command to install Docker
./host-b-worker.sh init

# Run the join command. It will prompt you to paste the command you copied from Host A.
./host-b-worker.sh join
```

Paste the `docker swarm join...` command when prompted and press Enter. The worker will connect to the manager.

### Step 3: Verify and Deploy the Application (Run on Host A)

Once all your workers have joined, return to the manager node (Host A) to verify the cluster and deploy the application.

```bash
# (On Host A) Check the status of your nodes
docker node ls

# Deploy the application stack
./host-a-manager.sh deploy
```

The services will now be distributed across the manager and worker nodes. You can check the status with `docker service ls`.

The application will be available at `http://<IP_OF_HOST_A>:8080/api/products`.

---

## Cleanup

To tear down the cluster, run the cleanup command on **all** nodes. It's best to start with the manager.

#### On the Manager Node (Host A):

```bash
./host-a-manager.sh cleanup
```
This removes the application stack and forces the manager to leave the swarm.

#### On the Worker Node(s) (Host B, C, etc.):

```bash
./host-b-worker.sh cleanup
```
This causes the worker to leave the swarm.