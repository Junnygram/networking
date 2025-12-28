#!/bin/bash

# A script to add network latency to a random container of the 'web' service.

# Check if latency argument is provided
if [ -z "$1" ]; then
  echo "Usage: $0 <latency>"
  echo "Example: $0 200ms"
  exit 1
fi

LATENCY=$1
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

echo "Selected container '$TARGET_CONTAINER_SHORT_ID' to add latency of $LATENCY."

# Check if a qdisc (queueing discipline) already exists. If so, change it. If not, add it.
docker exec $TARGET_CONTAINER tc qdisc show dev eth0 | grep -q "netem"
if [ $? -eq 0 ]; then
    echo "Existing netem qdisc found. Changing latency."
    docker exec $TARGET_CONTAINER tc qdisc change dev eth0 root netem delay $LATENCY
else
    echo "No existing netem qdisc. Adding new one."
    docker exec $TARGET_CONTAINER tc qdisc add dev eth0 root netem delay $LATENCY
fi

echo "Latency of $LATENCY added to container '$TARGET_CONTAINER_SHORT_ID'."
echo "To verify, you can ping another container's IP from within this one, or vice-versa."
echo "To remove the rule, run: docker exec $TARGET_CONTAINER tc qdisc del dev eth0 root"
