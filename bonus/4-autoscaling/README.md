# Bonus 4: Auto-Scaling Simulation

This directory contains a proof-of-concept script that simulates auto-scaling for a Docker Swarm service based on CPU usage.

**Disclaimer:** This is a **simulation** for educational purposes and is **not a production-ready solution**. Real-world auto-scaling is much more complex and should be handled by orchestrators like Kubernetes (with the Horizontal Pod Autoscaler) or cloud provider services.

## Components

1.  **`run.sh`**: The main script that manages the entire auto-scaling demo. It dynamically generates the `docker-compose.yml` file and contains the logic for deploying the service and running the scaler.

## How to Run (with `run.sh` script)

This directory includes a convenient script, `run.sh`, to automate setup and execution.

First, make the script executable:
```bash
chmod +x run.sh
```

### 1. Install Dependencies (First time on a new server)
This command will install Docker, Docker Compose, and `bc` (for calculations).
```bash
./run.sh install
```

### 2. Deploy the Service
This command will initialize Docker Swarm (if needed), generate the `docker-compose.yml`, and deploy the `cpu-scaler` stack.
```bash
./run.sh up
```

### 3. Run the Auto-Scaler
In a **separate terminal**, run the `scaler` command to start the monitoring loop.
```bash
./run.sh scaler
```

### 4. Generate CPU Load
In a third terminal, find a container ID of the `cpu-eater` service (`docker ps`). Then, use `docker exec` to run the `stress` command inside the container.
```bash
# Example:
docker exec <YOUR_CONTAINER_ID> stress --cpu 1 --timeout 120s
```

### 5. Observe the Scaling
- Watch the output of the `./run.sh scaler` terminal. When the CPU usage crosses the threshold, it will scale the service up.
- After the `stress` command finishes, the CPU usage will drop, and the scaler will eventually scale the service back down.

### 6. Stop the Services
This command will remove the stack, leave swarm mode, and clean up the generated `docker-compose.yml` file.
```bash
./run.sh down
```

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




![Latency](images/autoscaler.png)