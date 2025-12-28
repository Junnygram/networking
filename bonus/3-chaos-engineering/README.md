# Bonus 3: Chaos Engineering

This directory contains scripts to perform basic chaos engineering experiments on a running Docker service. The goal of chaos engineering is to intentionally inject failure into a system to test its resilience.

## Components

1.  **`run.sh`**: The main script to manage the chaos engineering demo. It dynamically generates the `docker-compose.yml` file and contains the logic for all chaos experiments.

## How to Run (with `run.sh` script)

This directory includes a convenient script, `run.sh`, to automate setup and execution.

First, make the script executable:
```bash
chmod +x run.sh
```

### 1. Install Dependencies (First time on a new server)
This command will install Docker and Docker Compose if they are not present.
```bash
./run.sh install
```

### 2. Start the Target Service
This command will generate the `docker-compose.yml` and start the `web` service with 3 replicas.
```bash
./run.sh up
```

### 3. Run a Chaos Experiment
You can now inject failures using the script's subcommands.

**A) Introduce Latency:**
Run the `latency` command with a delay value (e.g., `200ms`).
```bash
./run.sh latency 200ms
```
The script will pick a random container and add the specified latency to it.

**B) Kill a Container:**
Run the `kill` command.
```bash
./run.sh kill
```
The script will randomly select and kill one of the `web` containers. Docker's Swarm mode (enabled by `docker-compose`) will automatically start a new container to replace it, demonstrating self-healing.

### 4. Stop the Services
This command will stop the service and remove the generated `docker-compose.yml` file.
```bash
./run.sh down
```

## Cleanup

To remove the latency from a container, you can either restart it or run the following `tc` command (you'll need the container ID):
```bash
docker exec <CONTAINER_ID> tc qdisc del dev eth0 root
```

To stop the services, run:
```bash
docker-compose down
```

## Key Concepts Demonstrated

- **System Resilience:** Testing if your application can handle degraded network conditions or unexpected instance termination.
- **Self-Healing:** Observing how a container orchestrator (like Docker Swarm in this case) automatically recovers from failure by restarting terminated containers.
- **Targeted Failure Injection:** Using tools like `tc` and `docker kill` to precisely inject specific types of failures.
