# Bonus 4: Auto-Scaling Simulation

This directory contains a proof-of-concept script that simulates auto-scaling for a Docker Swarm service based on CPU usage.

**Disclaimer:** This is a **simulation** for educational purposes and is **not a production-ready solution**. Real-world auto-scaling is much more complex and should be handled by orchestrators like Kubernetes (with the Horizontal Pod Autoscaler) or cloud provider services.

## Components

1.  **`docker-compose.yml`**: Defines a service called `cpu-eater`. This service uses an image that has the `stress` utility, which we can use to artificially generate CPU load.

2.  **`simple-swarm-scaler.sh`**: This script continuously monitors the average CPU usage of the `cpu-eater` service.
    - If the average CPU goes **above** a defined threshold, it scales the service up.
    - If the average CPU goes **below** a defined threshold, it scales the service down.

## How to Run

1.  **Initialize Docker Swarm mode:**
    This script uses `docker service` commands, which require Swarm mode to be enabled.
    ```bash
    docker swarm init
    ```

2.  **Deploy the service:**
    Deploy the `cpu-eater` stack. We'll start with 1 replica.
    ```bash
    docker stack deploy -c docker-compose.yml cpu-scaler
    ```

3.  **Run the auto-scaler script:**
    Make the script executable and run it.
    ```bash
    chmod +x simple-swarm-scaler.sh
    ./simple-swarm-scaler.sh
    ```
    The script will now be watching the service in a loop.

4.  **Generate CPU Load:**
    Open another terminal. Find the container ID of the `cpu-eater` service.
    ```bash
    docker ps
    ```
    Now, use `docker exec` to run the `stress` command inside the container and generate load on 1 CPU core.
    ```bash
    docker exec <CONTAINER_ID> stress --cpu 1 --timeout 120s
    ```

5.  **Observe the scaling:**
    - Watch the output of the `simple-swarm-scaler.sh` script. When the CPU usage crosses the upper threshold, it will trigger a `docker service scale` command.
    - You can also watch the number of replicas with `docker service ls`.
    - After the `stress` command finishes (after 120 seconds), the CPU usage will drop. The scaler script will then detect this and scale the service back down.

## Cleanup

To stop the auto-scaler, press `Ctrl+C` in its terminal.

To remove the deployed stack:
```bash
docker stack rm cpu-scaler
```

To leave swarm mode:
```bash
docker swarm leave --force
```

## Key Concepts Demonstrated

- **Metrics Monitoring:** Scraping metrics (like CPU usage) from running containers.
- **Declarative Control Loop:** The script acts as a simple control loop, comparing the desired state (CPU below a threshold) with the actual state and taking action to reconcile it.
- **Orchestrator Integration:** Using orchestrator commands (`docker service scale`) to dynamically adjust the application's topology.
