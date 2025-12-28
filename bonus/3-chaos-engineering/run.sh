#!/bin/bash

# A script to manage the chaos engineering demo on a fresh Ubuntu server.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Helper functions to generate configuration files ---

generate_docker_compose_yml() {
cat <<EOF
version: '3.7'
services:
  web:
    image: nginx:1.21
    deploy:
      replicas: 3
EOF
}

# --- Functions ---

install_deps() {
    echo "--- Installing Docker and Docker Compose (if not present) ---"
    # Same install logic as other scripts...
    if ! command -v docker &> /dev/null; then
        sudo apt-get update -y && sudo apt-get install -y curl
        curl -fsSL https://get.docker.com -o get-docker.sh
        sudo sh get-docker.sh
        sudo usermod -aG docker $USER
        echo "Docker installed. Please log out and log back in."
    fi
    if ! command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d" -f4)
        sudo curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    fi
    echo "--- Dependencies are installed. ---"
}

start_services() {
    echo "--- Generating docker-compose.yml ---"
    generate_docker_compose_yml > docker-compose.yml
    echo "--- Starting service with 3 replicas ---"
    docker-compose up -d --scale web=3
    echo "Service 'web' is running. Use 'docker-compose ps' to see containers."
}

stop_services() {
    echo "--- Stopping services ---"
    docker-compose down -v
    echo "--- Cleaning up generated files ---"
    rm -f docker-compose.yml
    echo "Cleanup complete."
}

add_latency() {
    LATENCY=$1
    if [ -z "$LATENCY" ]; then
      echo "Usage: ./run.sh latency <latency>"
      echo "Example: ./run.sh latency 200ms"
      exit 1
    fi
    
    SERVICE_NAME="web"
    COMPOSE_PROJECT_NAME=$(basename "$PWD")
    CONTAINERS=($(docker ps -q --filter "name=${COMPOSE_PROJECT_NAME}_${SERVICE_NAME}"))
    if [ ${#CONTAINERS[@]} -eq 0 ]; then
        echo "No containers found for service '$SERVICE_NAME'"
        exit 1
    fi

    RANDOM_INDEX=$(( RANDOM % ${#CONTAINERS[@]} ))
    TARGET_CONTAINER=${CONTAINERS[$RANDOM_INDEX]}
    TARGET_CONTAINER_SHORT_ID=$(echo $TARGET_CONTAINER | cut -c 1-12)

    echo "Selected container '$TARGET_CONTAINER_SHORT_ID' to add latency of $LATENCY."
    docker exec $TARGET_CONTAINER tc qdisc add dev eth0 root netem delay $LATENCY 2>/dev/null || \
    docker exec $TARGET_CONTAINER tc qdisc change dev eth0 root netem delay $LATENCY
    echo "Latency of $LATENCY added to container '$TARGET_CONTAINER_SHORT_ID'."
}

kill_container() {
    SERVICE_NAME="web"
    COMPOSE_PROJECT_NAME=$(basename "$PWD")
    CONTAINERS=($(docker ps -q --filter "name=${COMPOSE_PROJECT_NAME}_${SERVICE_NAME}"))
    if [ ${#CONTAINERS[@]} -eq 0 ]; then
        echo "No containers found for service '$SERVICE_NAME'"
        exit 1
    fi

    RANDOM_INDEX=$(( RANDOM % ${#CONTAINERS[@]} ))
    TARGET_CONTAINER=${CONTAINERS[$RANDOM_INDEX]}
    TARGET_CONTAINER_SHORT_ID=$(echo $TARGET_CONTAINER | cut -c 1-12)

    echo "Selected container '$TARGET_CONTAINER_SHORT_ID' for termination."
    docker kill $TARGET_CONTAINER > /dev/null
    echo "Container '$TARGET_CONTAINER_SHORT_ID' has been killed. Docker should restart it."
}


show_help() {
    echo "Usage: ./run.sh [command]"
    echo
    echo "Commands:"
    echo "  install          Install Docker and Docker Compose."
    echo "  up               Generate config and start the 'web' service (default action)."
    echo "  down             Stop services and clean up generated files."
    echo "  latency <delay>  Add network latency to a random 'web' container (e.g., latency 200ms)."
    echo "  kill             Randomly kill one of the 'web' containers."
    echo "  help             Show this help message."
}

# --- Main Logic ---

CMD=${1:-up}

case "$CMD" in
    install) install_deps ;; 
    up) start_services ;; 
    down) stop_services ;; 
    latency) add_latency "$2" ;; 
    kill) kill_container ;; 
    help) show_help ;; 
    *) echo "Error: Unknown command: $CMD"; show_help; exit 1 ;; 
esac
