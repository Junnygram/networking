# Bonus 3: Chaos Engineering

This directory contains scripts to perform basic chaos engineering experiments on a running Docker service. The goal of chaos engineering is to intentionally inject failure into a system to test its resilience.

## Components

1.  **`docker-compose.yml`**: A simple setup that runs a single `nginx` service scaled to 3 replicas. We will use this as the target for our chaos experiments.

2.  **`introduce-latency.sh`**: This script uses `tc` (traffic control), a powerful Linux utility, to add a specified amount of latency to the network interface of a random container belonging to our `web` service.

3.  **`kill-container.sh`**: This script randomly selects one of the `web` service's containers and abruptly stops it using `docker kill`.

## How to Run

1.  **Start the target service:**
    First, deploy the `web` service with 3 replicas.
    ```bash
    docker-compose up -d --scale web=3
    ```
    You can see the running containers with `docker-compose ps`.

2.  **Run a Chaos Experiment:**

    **A) Introduce Latency:**
    Make the script executable and run it. You need to provide the network delay you want to add (e.g., `200ms`).
    ```bash
    chmod +x introduce-latency.sh
    ./introduce-latency.sh 200ms
    ```
    The script will pick a random container and add latency to it. If you run it again, it might pick a different container. You can verify the added latency by pinging the container.

    **B) Kill a Container:**
    Make the script executable and run it.
    ```bash
    chmod +x kill-container.sh
    ./kill-container.sh
    ```
    The script will randomly select and kill one of the `web` containers. Because we are running it as a Docker service, the orchestrator will automatically detect this and start a new container to replace it, demonstrating self-healing. You can observe this with `docker-compose ps`.

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
