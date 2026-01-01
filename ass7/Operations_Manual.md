# Project Operations Manual

## 1. Introduction

This manual provides instructions for the day-to-day operations of the e-commerce application deployed on the Docker Swarm cluster. All commands listed here should be run on a **manager node** of the Swarm, unless otherwise specified.

The application is deployed as a Docker Swarm "stack" named `myapp`. A stack is a group of interrelated services that share dependencies and can be orchestrated and scaled together.

## 2. Application Lifecycle Management

Managing the application stack is done using the `docker stack` command or the provided helper scripts from Assignment 6.

### 2.1. Starting the Application

To deploy or start the application for the first time, use the `deploy` command from the `host-a-manager.sh` script, which wraps the `docker stack deploy` command.

**Prerequisites:**
* You are on a manager node.
* A `docker-compose.yml` file is present in the current directory (`ass6/`).
* The Docker Swarm cluster is active.

**Command:**
```bash
# From the ass6/ directory
./host-a-manager.sh deploy
```

This command will create the overlay networks and start all the services defined in the `docker-compose.yml` file. If the stack is already running, this command will update the services to match the definitions in the file.

<!-- Image Placeholder: Output of the 'deploy' command -->

### 2.2. Stopping the Application

To stop and remove the entire application stack, including all services and networks:

**Command:**
```bash
docker stack rm myapp
```
or use the provided cleanup script:
```bash
./host-a-manager.sh cleanup
```
The `cleanup` command is more comprehensive as it also forces the manager node to leave the swarm. Use `docker stack rm myapp` for temporarily stopping the application without dismantling the swarm.

## 3. Monitoring and Health Checks

### 3.1. Checking Overall Service Status

To get a high-level overview of all services in the stack, use the `docker service ls` command.

**Command:**
```bash
docker service ls
```

**Expected Output:**
This command lists all services, their mode (replicated), the number of running replicas vs. desired replicas (`REPLICAS`), the image used, and the published ports. A healthy service will show the same number of running and desired replicas (e.g., `3/3`).

<!-- Image Placeholder: Output of `docker service ls` showing healthy services -->

### 3.2. Inspecting Individual Services

To get detailed information about a specific service, including the nodes it's running on and any error messages:

**Command:**
```bash
docker service ps myapp_<service_name>

# Example
docker service ps myapp_product-service
```

This command is your primary tool for diagnosing why a service might be failing to start or is in an unhealthy state. It will show the history of tasks (containers) for that service, including their status (`Running`, `Failed`, `Shutdown`).

<!-- Image Placeholder: Output of `docker service ps` for a specific service -->

### 3.3. Viewing Service Logs

To view the aggregated logs from all replicas of a specific service in real-time:

**Command:**
```bash
docker service logs -f myapp_<service_name>

# Example
docker service logs -f myapp_api-gateway
```
This is extremely useful for debugging application-level errors, as it streams the `stdout` and `stderr` from all containers in the service to your terminal.

## 4. Scaling Services

One of the key benefits of Docker Swarm is the ability to scale services up or down with a single command.

### 4.1. Scaling a Service Manually

To change the number of replicas for a service:

**Command:**
```bash
docker service scale myapp_<service_name>=<number_of_replicas>

# Example: Scale the product-service to 5 replicas
docker service scale myapp_product-service=5

# Example: Scale it back down to 3 replicas
docker service scale myapp_product-service=3
```

Docker Swarm will automatically start or stop containers to meet the new desired replica count, distributing them across the available nodes in the cluster.

<!-- Image Placeholder: Output of `docker service scale` command -->

## 5. Troubleshooting Common Issues

### Issue: A service shows `0/1` replicas running.
1.  **Inspect the service:** Run `docker service ps myapp_<service_name>`.
2.  **Check the "ERRORS" column:** This will often tell you exactly why the container failed (e.g., "executable file not found", "port is already allocated").
3.  **Check the logs:** If the container starts and then immediately fails, check the logs with `docker service logs myapp_<service_name>`. This will reveal application-level errors, like a failure to connect to the database.
4.  **Check for resource constraints:** If the node is out of memory or CPU, the service may not be able to start. Check `docker stats` on the individual nodes.

### Issue: Services on different hosts cannot communicate.
1.  **Check Firewalls:** This is the most common cause. Ensure that your cloud provider's security group or your hosts' firewalls are configured to allow traffic on the necessary Swarm ports (TCP 2377, TCP/UDP 7946, UDP 4789).
2.  **Verify Overlay Networks:** On the manager, run `docker network ls` to ensure the `overlay` networks exist. Run `docker network inspect myapp_backend_net` to see which containers are attached.
3.  **Check Node Status:** Run `docker node ls` on the manager. If a node is `Down` or `Unreachable`, services on that node will not be able to communicate.

### Issue: Public endpoint (`http://<HOST_IP>:8080`) is not responding.
1.  **Check the Nginx service:** Run `docker service ps myapp_nginx-lb`. Ensure it is running.
2.  **Check firewall on the host:** Ensure that traffic to port `8080` is allowed on the host you are trying to connect to.
3.  **Check the ingress network:** Swarm's ingress routing mesh handles this. If it's not working, this could indicate a deeper issue with the Docker installation or host networking. A simple first step is to restart the Docker daemon on all nodes (`sudo systemctl restart docker`) and see if the issue resolves.