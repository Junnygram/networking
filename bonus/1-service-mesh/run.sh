#!/bin/bash

# A script to manage the service mesh demo on a fresh Ubuntu server.

set -e # Exit immediately if a command exits with a non-zero status.

# --- Helper functions to generate configuration files ---

generate_docker_compose_yml() {
cat <<EOF
version: '3.7'
services:
  frontend:
    # A simple container we can use to send requests from
    image: alpine:3.15
    # Keep it running so we can exec into it
    command: ["sleep", "infinity"]

  backend:
    # A simple web server to act as our backend service
    image: nginx:1.21
    # Nginx runs on port 80 by default
  
  envoy:
    # The envoy proxy
    image: envoyproxy/envoy:v1.20.0
    ports:
      # Expose the proxy's listener port to the host for optional direct testing
      - "8000:8000"
    volumes:
      # Mount the envoy configuration file
      - ./envoy.yaml:/etc/envoy/envoy.yaml
    # The command to start envoy with our config
    command: /usr/local/bin/envoy -c /etc/envoy/envoy.yaml
EOF
}

generate_envoy_yaml() {
cat <<EOF
static_resources:
  listeners:
  - name: listener_0
    address:
      socket_address: { address: 0.0.0.0, port_value: 8000 }
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          stat_prefix: ingress_http
          http_filters:
          - name: envoy.filters.http.router
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match: { prefix: "/" }
                route:
                  # Route all traffic to the 'backend' cluster
                  cluster: backend_service

  clusters:
  - name: backend_service
    connect_timeout: 0.25s
    type: LOGICAL_DNS
    # Or use 'STRICT_DNS' for resolving all DNS entries
    dns_lookup_family: V4_ONLY
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: backend_service
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                # The hostname 'backend' is resolved by Docker's DNS
                address: backend
                port_value: 80
EOF
}

# --- Functions ---

check_deps() {
    if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
        echo "Error: Docker or Docker Compose not found."
        echo "Please run './run.sh install' first."
        exit 1
    fi
}

install_deps() {
    echo "--- Updating package list and installing dependencies ---"
    sudo apt-get update -y
    sudo apt-get install -y curl

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
    echo "--- Generating docker-compose.yml and envoy.yaml ---"
    generate_docker_compose_yml > docker-compose.yml
    generate_envoy_yaml > envoy.yaml
    echo "--- Starting services with Docker Compose ---"
    docker-compose up --build -d
    echo "Services are running in the background."
}

stop_services() {
    check_deps
    echo "--- Stopping services ---"
    docker-compose down
    echo "--- Cleaning up generated configuration files ---"
    rm -f docker-compose.yml envoy.yaml
    echo "Services stopped and config files removed."
}

test_connection() {
    check_deps
    echo "--- Testing connection from 'frontend' to 'backend' via Envoy ---"
    echo "Waiting for services to be ready..."
    sleep 5 
    docker-compose exec frontend sh -c "apk add --no-cache curl && curl -v http://envoy:8000"
}

show_help() {
    echo "Usage: ./run.sh [command]"
    echo
    echo "Commands:"
    echo "  install   Install Docker and Docker Compose."
    echo "  up        Generate config files and start the services (default action)."
    echo "  down      Stop and remove the services and generated config files."
    echo "  test      Run a test request to verify the proxy."
    echo "  help      Show this help message."
}

# --- Main Logic ---

# Default to 'up' if no command is given
CMD=${1:-up}

case "$CMD" in
    install) install_deps ;;
    up) start_services ;;
    down) stop_services ;;
    test) test_connection ;;
    help) show_help ;;
    *) echo "Error: Unknown command: $CMD"; show_help; exit 1 ;;
esac