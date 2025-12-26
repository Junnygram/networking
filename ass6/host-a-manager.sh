#!/bin/bash
# ===================================================================================
# HOST A (MANAGER) SETUP SCRIPT - Assignment 6: Multi-Host Networking (v2)
#
# This script manages the Docker Swarm Manager node.
#
# ===================================================================================

set -e

# --- Command Functions ---

do_init() {
    local MANAGER_IP=$1
    if [ -z "$MANAGER_IP" ]; then
        echo "Usage: $0 init <MANAGER_IP>" >&2
        echo "Please provide the IP address for the manager to advertise." >&2
        exit 1
    fi

    # 1. Check for Docker permissions.
    if ! docker info > /dev/null 2>&1; then
        echo "❌ ERROR: Your user ('$USER') cannot connect to the Docker daemon."
        echo "This is likely because you have just been added to the 'docker' group."
        echo ""
        echo "💡 Please run the following command to start a new shell with the correct permissions:"
        echo "   newgrp docker"
        echo ""
        echo "Then, from the new shell, re-run this script: ./updtedhost.sh init $MANAGER_IP"
        exit 1
    fi
    echo "✅ Docker permissions are correct."

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
}

do_deploy() {
    if ! docker info > /dev/null 2>&1; then
        echo "❌ ERROR: Docker permissions incorrect. Please run 'newgrp docker' and try again." >&2
        exit 1
    fi
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
    if ! docker info > /dev/null 2>&1; then
        echo "❌ ERROR: Docker permissions incorrect. Please run 'newgrp docker' and try again." >&2
        exit 1
    fi
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
