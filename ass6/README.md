# Assignment 6: Multi-Host Swarm Deployment (Final)

This directory contains the scripts to deploy a microservices application across a multi-host environment using Docker Swarm.

## Final Scripts

*   `manager-setup.sh`: A one-time setup script to initialize the Swarm on your manager node.
*   `worker-setup.sh`: A one-time setup script to join a worker node to the Swarm.
*   `manager.sh`: The main script for managing your application lifecycle (generating source code, building images, deploying, and cleaning up).

---

## Final Workflow

### Part 1: One-Time Swarm Setup
(You only need to do this once to connect your machines).

#### 1. Setup Manager Node
*On your designated manager VM:*
1.  Ensure Docker is installed and your user has permissions (you may need to run `sudo usermod -aG docker $USER` and then `newgrp docker`).
2.  Place the `manager-setup.sh` script on this machine.
3.  Make it executable: `chmod +x manager-setup.sh`
4.  Run it with the manager's private IP: `./manager-setup.sh <your-manager-private-ip>`
5.  Copy the `docker swarm join...` command it provides.

#### 2. Setup Worker Node
*On your designated worker VM:*
1.  Ensure Docker is installed and your user has permissions.
2.  Place the `worker-setup.sh` script on this machine.
3.  Make it executable: `chmod +x worker-setup.sh`
4.  Run the script: `./worker-setup.sh`
5.  Paste the join token from the manager when prompted.

#### 3. Configure Cloud Security Group (CRITICAL)
Before proceeding, ensure your cloud firewall (e.g., AWS Security Group) is configured to allow communication between your instances. The easiest way is to add an **Inbound Rule** to your security group:
*   **Type:** `All traffic`
*   **Source:** The **ID of the security group itself** (e.g., `sg-01234abc...`).

This allows all instances within the same group to communicate freely.

---

### Part 2: Deploying Your Application

(This is done on the **manager VM** using the `manager.sh` script).

1.  **On the Manager VM**, place the `manager.sh` script.
2.  Make it executable:
    ```bash
    chmod +x manager.sh
    ```
3.  **Generate the source code files:**
    ```bash
    ./manager.sh outputfile
    ```
4.  **Build the Docker images from the source files:**
    ```bash
    ./manager.sh build
    ```
5.  **Deploy the application stack:**
    ```bash
    ./manager.sh deploy
    ```

After these steps, your application will be running. You can check its status with `docker service ls` on the manager. All services will be running on the manager node. You can access the API Gateway at `http://<your-manager-public-ip>:8080/api/products`.

---

### Part 3: Cleaning Up

To remove the deployed application stack from your swarm, run the following on your **manager VM**:
```bash
./manager.sh clean
```
