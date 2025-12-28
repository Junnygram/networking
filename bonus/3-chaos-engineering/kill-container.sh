#!/bin/bash

# A script to randomly kill a container belonging to the 'web' service.

SERVICE_NAME="web"
COMPOSE_PROJECT_NAME=$(basename "$PWD")
SERVICE_NAME_FULL="${COMPOSE_PROJECT_NAME}_${SERVICE_NAME}"

# Get the list of container IDs for the service
CONTAINERS=($(docker ps -q --filter "name=${SERVICE_NAME_FULL}"))

# Check if any containers are running
if [ ${#CONTAINERS[@]} -eq 0 ]; then
    echo "No containers found for service '$SERVICE_NAME'"
    exit 1
fi

# Select a random container from the list
RANDOM_INDEX=$(( RANDOM % ${#CONTAINERS[@]} ))
TARGET_CONTAINER=${CONTAINERS[$RANDOM_INDEX]}
TARGET_CONTAINER_SHORT_ID=$(echo $TARGET_CONTAINER | cut -c 1-12)


echo "Selected container '$TARGET_CONTAINER_SHORT_ID' for termination."

# Kill the container
docker kill $TARGET_CONTAINER > /dev/null

echo "Container '$TARGET_CONTAINER_SHORT_ID' has been killed."
echo "Docker Swarm should automatically start a new container to replace it."
echo "Check the status with 'docker-compose ps'."
