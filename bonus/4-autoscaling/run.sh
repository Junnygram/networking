#!/bin/bash

# A script to manage the auto-scaling demo on a fresh Ubuntu server.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Helper functions to generate configuration files ---

generate_docker_compose_yml() {
cat <<EOF
version: '3.7'
services:
  cpu-eater:
    image: polinux/stress
    command: ["sleep", "infinity"]
    deploy:
      replicas: 1
      resources:
        limits:
          cpus: '0.50'
EOF
}

# --- Functions ---

check_deps() {
    if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
        echo "Error: Docker or Docker Compose not found."
        echo "Please run './run.sh install' first."
        exit 1
    fi
    if ! command -v bc &> /dev/null; then
        echo "Error: 'bc' (basic calculator) is not installed."
        echo "Please run './run.sh install' first."
        exit 1
    fi
}

install_deps() {
    echo "--- Updating package list and installing dependencies ---"
    sudo apt-get update -y
    sudo apt-get install -y curl bc

    echo "--- Installing Docker ---"
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        echo "Docker installed. Please log out and log back in for group changes to take effect, or run 'newgrp docker'."
    else
        echo "Docker is already installed."
    fi

    echo "--- Installing Docker Compose ---"
    if ! command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
        sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        echo "Docker Compose ${COMPOSE_VERSION} installed."
    else
        echo "Docker Compose is already installed."
    fi
    
    echo "--- Installation complete! ---"
    echo "IMPORTANT: You may need to log out and log back in to use 'docker' without 'sudo'."
}

start_services() {
    check_deps
    echo "--- Initializing Docker Swarm (if not active) ---"
    docker info | grep -q "Swarm: active" || docker swarm init
    
    echo "--- Generating docker-compose.yml ---"
    generate_docker_compose_yml > docker-compose.yml
    
    echo "--- Deploying stack 'cpu-scaler' ---"
    docker stack deploy -c docker-compose.yml cpu-scaler
    echo "Stack deployed. Use './run.sh scaler' to start the monitor."
}

stop_services() {
    check_deps
    echo "--- Removing stack 'cpu-scaler' ---"
    docker stack rm cpu-scaler
    echo "--- Leaving Swarm mode ---"
    docker swarm leave --force
    echo "--- Cleaning up generated files ---"
    rm -f docker-compose.yml
    echo "Cleanup complete."
}

run_scaler() {
    check_deps
    SERVICE_NAME="cpu-scaler_cpu-eater"
    SCALE_UP_THRESHOLD=50
    SCALE_DOWN_THRESHOLD=10
    MIN_REPLICAS=1
    MAX_REPLICAS=5
    CHECK_INTERVAL=10

    echo "--- Starting simple auto-scaler for service: $SERVICE_NAME ---"
    while true; do
        CURRENT_REPLICAS=$(docker service ls --filter "name=${SERVICE_NAME}" --format "{{.Replicas}}" | cut -d'/' -f1)
        if [ -z "$CURRENT_REPLICAS" ]; then
          echo "[$(date +%T)] Service not found. Waiting..."
          sleep $CHECK_INTERVAL
          continue
        fi
        
        # Get container IDs for the running service
        CONTAINER_IDS=$(docker ps -q --filter "label=com.docker.swarm.service.name=${SERVICE_NAME}")
        
        if [ -z "$CONTAINER_IDS" ]; then
            echo "[$(date +%T)] No running containers found. Scaling down to min replicas."
            docker service scale ${SERVICE_NAME}=${MIN_REPLICAS}
            sleep $CHECK_INTERVAL
            continue
        fi

        # Get stats for all containers of the service
        CPU_STATS=$(docker stats --no-stream --format "{{.CPUPerc}}" $CONTAINER_IDS)

        TOTAL_CPU=0; COUNT=0
        for CPU in $CPU_STATS; do
            CPU_VAL=$(echo $CPU | sed 's/%//'); TOTAL_CPU=$(echo "$TOTAL_CPU + $CPU_VAL" | bc); COUNT=$((COUNT + 1))
        done
        AVG_CPU=$(echo "scale=2; $TOTAL_CPU / $COUNT" | bc)

        echo "[$(date +%T)] Replicas: $CURRENT_REPLICAS | Avg CPU: $AVG_CPU%"

        if (( $(echo "$AVG_CPU > $SCALE_UP_THRESHOLD" | bc -l) )) && [ "$CURRENT_REPLICAS" -lt "$MAX_REPLICAS" ]; then
            NEW_REPLICAS=$((CURRENT_REPLICAS + 1))
            echo "  -> SCALE UP to $NEW_REPLICAS replicas."
            docker service scale ${SERVICE_NAME}=${NEW_REPLICAS}
        elif (( $(echo "$AVG_CPU < $SCALE_DOWN_THRESHOLD" | bc -l) )) && [ "$CURRENT_REPLICAS" -gt "$MIN_REPLICAS" ]; then
            NEW_REPLICAS=$((CURRENT_REPLICAS - 1))
            echo "  -> SCALE DOWN to $NEW_REPLICAS replicas."
            docker service scale ${SERVICE_NAME}=${NEW_REPLICAS}
        else
            echo "  -> HOLD."
        fi
        
        sleep $CHECK_INTERVAL
    done
}

show_help() {
    echo "Usage: ./run.sh [command]"
    echo
    echo "Commands:"
    echo "  install   Install Docker, Docker Compose, and other dependencies."
    echo "  up        Deploys the stack to Docker Swarm (default action)."
    echo "  down      Removes the stack and cleans up."
    echo "  scaler    Run the auto-scaling monitor loop."
    echo "  help      Show this help message."
    echo
    echo "To test, run './run.sh up', then in another terminal run './run.sh scaler'."
    echo "Then, find a container ID with 'docker ps' and generate load with:"
    echo "docker exec <CONTAINER_ID> stress --cpu 1 --timeout 120s"
}

# --- Main Logic ---

CMD=${1:-up}

case "$CMD" in
    install) install_deps ;; 
    up) start_services ;; 
    down) stop_services ;; 
    scaler) run_scaler ;; 
    help) show_help ;; 
    *) echo "Error: Unknown command: $CMD"; show_help; exit 1 ;; 
esac
