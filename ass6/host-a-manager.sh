#!/bin/bash
# ===================================================================================
# HOST A (MANAGER) SETUP SCRIPT - Assignment 6: Multi-Host Networking (v2.1)
#
# This script manages the Docker Swarm Manager node.
#
# ===================================================================================

set -e

# --- Helper Functions ---
check_docker_permissions() {
    if ! docker info > /dev/null 2>&1; then
        echo "❌ ERROR: Your user ('$USER') cannot connect to the Docker daemon."
        echo "This is likely because you have just been added to the 'docker' group."
        echo ""
        echo "💡 Please run 'newgrp docker' or log out and log back in to apply the change."
        exit 1
    fi
    echo "✅ Docker permissions are correct."
}

install_docker() {
    if command -v docker >/dev/null; then
        echo "✅ Docker is already installed."
    else
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
        echo "✅ Docker installation complete."
    fi
    sudo groupadd docker || true # Ensure docker group exists
    sudo usermod -aG docker "$USER"
    echo "✅ User '$USER' added to 'docker' group (if not already)."
    echo "IMPORTANT: If you just installed Docker or added yourself to the group, you MAY need to run 'newgrp docker' or log out/in."
}

# --- Command Functions ---

do_init() {
    local MANAGER_IP=$1
    if [ -z "$MANAGER_IP" ]; then
        echo "Usage: $0 init <MANAGER_IP>" >&2
        echo "Please provide the IP address for the manager to advertise." >&2
        exit 1
    fi

    # 1. Ensure Docker is installed and permissions are set.
    install_docker
    check_docker_permissions

    # Added: Restart Docker daemon to ensure a clean state before Swarm init
    echo "--- Restarting Docker Daemon for a clean Swarm state ---"
    sudo systemctl restart docker
    sleep 5 # Give Docker a moment to restart

    # 2. Initialize the Swarm.
    echo "--- Initializing Docker Swarm ---"
    # Check if this node is already an active Swarm manager
    if docker info --format '{{.Swarm.ControlAvailable}}' | grep -q "true"; then
        echo "✅ This node is already an active Swarm manager."
    else
        echo "Attempting to initialize Docker Swarm..."
        docker swarm init --advertise-addr "$MANAGER_IP"
        echo "--- ✅ Docker Swarm Initialized as Manager ---"
    fi

    # 3. Display the join token.
    echo ""
    echo "⬇️⬇️⬇️ RUN THIS COMMAND ON YOUR WORKER NODES ⬇️⬇️⬇️"
    JOIN_CMD=$(docker swarm join-token worker | grep "docker swarm join")
    echo "$JOIN_CMD"
    echo "⬆️⬆️⬆️ RUN THIS COMMAND ON YOUR WORKER NODES ⬆️⬆️⬆️"
    echo ""
    echo "💡 IMPORTANT: For the worker to join successfully, your cloud provider's firewall (e.g., AWS Security Group)"
    echo "must allow traffic between the manager and worker nodes. See the README for details."

}

do_deploy() {
    check_docker_permissions
    if [ ! -f "docker-compose.yml" ]; then
        echo "❌ ERROR: docker-compose.yml not found in the current directory." >&2
        exit 1
    fi
    
    echo "--- Deploying application stack 'myapp' to the Swarm ---"
    docker stack deploy -c docker-compose.yml myapp
    echo "✅ Stack 'myapp' deployed successfully."
    echo "Run 'docker service ls' to check the status of the services."
}

do_cleanup() {
    check_docker_permissions
    echo "--- Cleaning up Docker Swarm ---"
    echo "Removing application stack 'myapp'..."
    docker stack rm myapp || echo "Stack 'myapp' not found or already removed."
    
    sleep 5 

    echo "Forcing this node to leave the swarm..."
    docker swarm leave --force || echo "Node was not part of a swarm."
    
    echo "✅ Cleanup complete."
}

# --- Main script logic ---
CMD=$1

# Make script executable
chmod +x "$0"

case "$CMD" in
    init) do_init "$2";;
    deploy) do_deploy;;
    cleanup) do_cleanup;;
    *)
        echo "Usage: $0 {init|deploy|cleanup} [options]" >&2
        echo "  - init <MANAGER_IP>: Initializes the Swarm."
        echo "  - deploy: Deploys the 'myapp' stack from docker-compose.yml."
        echo "  - cleanup: Removes the stack and leaves the Swarm."
        exit 1
        ;;
esac

exit 0
