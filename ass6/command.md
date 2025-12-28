# Assignment 6: Manual Docker Swarm Deployment Commands

This document provides the step-by-step commands to manually set up a multi-host Docker Swarm cluster and deploy the application stack. This process reflects the definitive "Production" workflow for the project.

**Prerequisites:**
*   You have at least two hosts (e.g., VMs) that can communicate with each other over the network. One will be the **manager**, the others will be **workers**.
*   Docker is installed on all hosts, and your user has permission to run `docker` commands.
*   Firewalls between the hosts are configured to allow Swarm traffic (TCP 2377, TCP/UDP 7946, UDP 4789).

---

## 1. Set Up the Swarm Cluster

### Step 1: Initialize the Swarm Manager
On the host you designate as the manager, run the `docker swarm init` command. You must provide the IP address that other nodes will use to connect to the manager.

```bash
# On the Manager Host
# Replace <MANAGER_IP> with the actual private IP of your manager host
docker swarm init --advertise-addr <MANAGER_IP>
```
This command will do two things:
1.  Initialize the current node as a Swarm manager.
2.  Print a `docker swarm join` command containing a secret token. **Copy this entire command.**

**Example Output:**
```
Swarm initialized: current node (dxn1...9c) is now a manager.

To add a worker to this swarm, run the following command:

    docker swarm join --token SWMTKN-1-3...2-b...c <MANAGER_IP>:2377

To add a manager to this swarm, run 'docker swarm join-token manager' and follow the instructions.
```

### Step 2: Join Worker Nodes to the Swarm
On each worker host, paste and run the `docker swarm join` command you copied from the manager.

```bash
# On each Worker Host
docker swarm join --token <YOUR_TOKEN> <MANAGER_IP>:2377
```

### Step 3: Verify the Cluster
Go back to the **manager host** and verify that all nodes have joined successfully.

```bash
# On the Manager Host
docker node ls
```
You should see all your nodes listed with a status of `Ready`.

---

## 2. Deploy the Application Stack

This process is performed on the **manager host**. It uses the `docker-compose.yml` file to deploy the full, replicated, multi-service application.

### Step 1: Create the `docker-compose.yml` File
Ensure the following `docker-compose.yml` file is present on your manager node. This file defines the final architecture, using pre-built images from Docker Hub and specifying service replicas and overlay networks.

```bash
cat << 'EOF' > docker-compose.yml
version: '3.8'
services:
  nginx-lb:
    image: junioroyewunmi/nginx-lb:1.0
    ports: [ "8080:80" ]
    networks: [ frontend_net ]
    depends_on: [ api-gateway ]
    deploy:
      replicas: 1
      placement: { constraints: [node.role == manager] }
  api-gateway:
    image: junioroyewunmi/api-gateway:1.0
    networks: [ frontend_net, backend_net ]
    depends_on: [ product-service, order-service ]
    deploy: { replicas: 2 }
  product-service:
    image: junioroyewunmi/product-service:1.0
    networks: [ backend_net, cache_net ]
    depends_on: [ redis-cache ]
    environment: { REDIS_HOST: redis-cache }
    deploy: { replicas: 3 }
  order-service:
    image: junioroyewunmi/order-service:1.0
    networks: [ backend_net, database_net ]
    depends_on: [ postgres-db ]
    environment:
      DB_HOST: postgres-db
      DB_NAME: orders
      DB_USER: postgres
      DB_PASSWORD: postgres
    deploy: { replicas: 2 }
  redis-cache:
    image: redis:7-alpine
    networks: [ cache_net ]
    deploy: { replicas: 1 }
  postgres-db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: orders
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
    volumes: [ postgres_data:/var/lib/postgresql/data ]
    networks: [ database_net ]
    deploy:
      replicas: 1
      placement: { constraints: [node.role == manager] }
networks:
  frontend_net: { driver: overlay }
  backend_net: { driver: overlay }
  cache_net: { driver: overlay }
  database_net: { driver: overlay }
volumes:
  postgres_data:
EOF
```

### Step 2: Deploy the Stack
Use the `docker stack deploy` command to deploy the application. The `-c` flag specifies the compose file, and `myapp` is the name we give to our stack.

```bash
# On the Manager Host
docker stack deploy -c docker-compose.yml myapp
```
Docker Swarm will now pull the required images and distribute the containers (tasks) across the nodes in the cluster according to the `deploy` policies in the compose file.

## 3. Verify and Manage the Deployment

### Verify the Services
Check the status of your deployed services.
```bash
# On the Manager Host
docker service ls
```
This will show you how many replicas of each service are running.

### Test the Application
The Nginx service is exposed on port `8080` on every node in the Swarm. You can send a request to the public IP of *any* node in the cluster.
```bash
curl http://<ANY_NODE_IP>:8080/api/products
```

## 4. Clean Up

### Step 1: Remove the Application Stack
This command removes all services, networks, and secrets associated with the stack.

```bash
# On the Manager Host
docker stack rm myapp
```

### Step 2: Disband the Swarm
To completely dismantle the cluster:
```bash
# On each Worker Host
docker swarm leave

# On the Manager Host
docker swarm leave --force
```

---

### Alternative "Development" Workflow

The `ass6` folder also contains a `manager.sh` script that provides a simplified, single-node workflow. It is useful for development and testing but does not represent the final multi-host architecture.

**Manual Steps for the Development Workflow:**
1.  **Generate Files:** `bash manager.sh outputfile`
2.  **Build Local Images:** `bash manager.sh build`
3.  **Deploy to Manager Node:** `bash manager.sh deploy`
4.  **Clean Up:** `bash manager.sh clean`

This workflow uses locally built images and deploys a smaller, two-service stack that is constrained to only run on the manager node.
