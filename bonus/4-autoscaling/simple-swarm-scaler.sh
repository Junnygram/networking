#!/bin/bash

# A simple auto-scaling script for a Docker Swarm service based on CPU usage.
# WARNING: This is for educational purposes only. Not for production use.

# --- Configuration ---
SERVICE_NAME="cpu-scaler_cpu-eater"
SCALE_UP_THRESHOLD=50   # CPU percentage to scale up at
SCALE_DOWN_THRESHOLD=10 # CPU percentage to scale down at
MIN_REPLICAS=1
MAX_REPLICAS=5
CHECK_INTERVAL=10 # Seconds to wait between checks

echo "Starting simple auto-scaler for service: $SERVICE_NAME"
echo "Configuration:"
echo "  Scale-up CPU threshold:   $SCALE_UP_THRESHOLD%"
echo "  Scale-down CPU threshold: $SCALE_DOWN_THRESHOLD%"
echo "  Min replicas:             $MIN_REPLICAS"
echo "  Max replicas:             $MAX_REPLICAS"
echo "  Check interval:           $CHECK_INTERVAL seconds"
echo "------------------------------------------------"

# --- Main Loop ---
while true; do
    # Get the number of running replicas
    CURRENT_REPLICAS=$(docker service ls --filter "name=${SERVICE_NAME}" --format "{{.Replicas}}" | cut -d'/' -f1)
    
    # Get stats for all containers of the service, format it to get just the CPU percentage, and remove the '%' sign.
    CPU_STATS=$(docker stats --no-stream --format "{{.CPUPerc}}" "name=${SERVICE_NAME}")
    
    if [ -z "$CPU_STATS" ]; then
        echo "No running containers found for service '$SERVICE_NAME'. Waiting..."
        sleep $CHECK_INTERVAL
        continue
    fi

    # Calculate the average CPU usage across all containers
    TOTAL_CPU=0
    COUNT=0
    for CPU in $CPU_STATS; do
        CPU_VAL=$(echo $CPU | sed 's/%//')
        TOTAL_CPU=$(echo "$TOTAL_CPU + $CPU_VAL" | bc)
        COUNT=$((COUNT + 1))
    done
    AVG_CPU=$(echo "scale=2; $TOTAL_CPU / $COUNT" | bc)

    echo "[$(date +%T)] Current Replicas: $CURRENT_REPLICAS | Average CPU: $AVG_CPU%"

    # --- Scaling Logic ---
    
    # Scale Up
    if (( $(echo "$AVG_CPU > $SCALE_UP_THRESHOLD" | bc -l) )) && [ "$CURRENT_REPLICAS" -lt "$MAX_REPLICAS" ]; then
        NEW_REPLICAS=$((CURRENT_REPLICAS + 1))
        echo "  -> SCALE UP: Average CPU ($AVG_CPU%) is above threshold ($SCALE_UP_THRESHOLD%). Scaling to $NEW_REPLICAS replicas."
        docker service scale ${SERVICE_NAME}=${NEW_REPLICAS}
    # Scale Down
    elif (( $(echo "$AVG_CPU < $SCALE_DOWN_THRESHOLD" | bc -l) )) && [ "$CURRENT_REPLICAS" -gt "$MIN_REPLICAS" ]; then
        NEW_REPLICAS=$((CURRENT_REPLICAS - 1))
        echo "  -> SCALE DOWN: Average CPU ($AVG_CPU%) is below threshold ($SCALE_DOWN_THRESHOLD%). Scaling to $NEW_REPLICAS replicas."
        docker service scale ${SERVICE_NAME}=${NEW_REPLICAS}
    else
        echo "  -> HOLD: No scaling action needed."
    fi
    
    sleep $CHECK_INTERVAL
done
