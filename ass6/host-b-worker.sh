#!/bin/bash
# ===================================================================================
# HOST B (WORKER) SETUP SCRIPT - Assignment 6: Multi-Host Networking
#
# This script manages a Docker Swarm Worker node.
#
# Usage:
#   ./host-b-worker.sh init
#       - Installs Docker Engine on the worker machine.
#
#   ./host-b-worker.sh join
#       - Prompts for the join command from the manager to connect to the Swarm.
#
#   ./host-b-worker.sh cleanup
#       - Makes the node leave the Swarm.
#
# ===================================================================================

set -e

# --- Helper Functions ---
check_docker_permissions() {
    if ! docker info > /dev/null 2>&1; then
        echo "❌ ERROR: Your user ('$USER') cannot connect to the Docker daemon."
        echo "This is likely because you have just been added to the 'docker' group."
        echo ""
        echo "💡 Please run the following command to start a new shell with the correct permissions:"
        echo "   newgrp docker"
        echo ""
        echo "Then, from the new shell, re-run this script."
        exit 1
    fi
    echo "✅ Docker permissions are correct."
}

install_docker() {
    if command -v docker >/dev/null; then
        echo "✅ Docker is already installed."
        if ! docker info >/dev/null 2>&1; then
             echo "‼️ User '$USER' cannot run Docker commands without sudo."
             echo "   Attempting to add user to the 'docker' group..."
             sudo usermod -aG docker "$USER"
             echo "   SUCCESS: User added to 'docker' group."
             echo "   IMPORTANT: Run 'newgrp docker' or log out/in to apply the change."
        fi
        return 0
    fi

    echo "--- Installing Docker Engine ---"
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    sudo usermod -aG docker "$USER"
    echo "✅ Docker installation complete."
    echo "✅ User '$USER' added to the 'docker' group."
    echo "IMPORTANT: You MUST run 'newgrp docker' in your shell or log out and back in for this change to take effect before proceeding."
}

# --- Command Functions ---
do_init() {
    install_docker
}

do_join() {
    check_docker_permissions
    
    echo "--- Joining a Docker Swarm ---"
    if docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        echo "✅ This node is already part of a Swarm. Leaving first..."
        docker swarm leave --force || echo "Could not leave swarm, might not be part of one."
        sleep 2
    fi

    echo "Please paste the full 'docker swarm join ...' command from the manager node:"
    read -p "> " JOIN_CMD

    if [[ -z "$JOIN_CMD" ]]; then
        echo "❌ No command entered. Aborting."
        exit 1
    fi
    
    echo "Executing: $JOIN_CMD"
    $JOIN_CMD

    echo "✅ This node has successfully joined the Swarm."
}

do_cleanup() {
    check_docker_permissions
    echo "--- Leaving the Docker Swarm ---"
    docker swarm leave || echo "Node was not part of a swarm."
    echo "✅ Cleanup complete."
}


# --- Main script logic ---
CMD=$1

# Make script executable
chmod +x "$0"

case "$CMD" in
    init) do_init;; 
    join) do_join;; 
    cleanup) do_cleanup;; 
    *) 
        echo "Usage: $0 {init|join|cleanup}" >&2
        echo "  - init: Installs Docker."
        echo "  - join: Prompts for the manager's command to join the Swarm."
        echo "  - cleanup: Forces the node to leave the Swarm."
        exit 1
        ;; 
esac

exit 0
