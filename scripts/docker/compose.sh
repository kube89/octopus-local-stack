#!/bin/bash

# Docker Compose helper functions

# Get container name for a specific service (in the current compose context)
# Usage: get_container_name <service_name>
get_container_name() {
    local service="$1"
    # Try to get the name via compose
    local name
    name=$(docker compose ps --format '{{.Name}}' "$service" 2>/dev/null | head -n 1)
    
    # Fallback to direct name construction if compose not running yet (risky but sometimes needed)
    if [ -z "$name" ]; then
        # Check standard naming pattern
        name=$(docker ps -a --format '{{.Names}}' | grep -E "[-_]${service}[-_][0-9]+$" | head -n 1)
    fi
    echo "$name"
}

# Check if a container is running
# Usage: is_container_running <container_name>
is_container_running() {
    local container="$1"
    [ -z "$container" ] && return 1
    
    local state
    state=$(docker inspect --format '{{.State.Status}}' "$container" 2>/dev/null)
    [ "$state" == "running" ]
}

# Check if a service is up and running via Compose
# Usage: is_service_running <service_name>
is_service_running() {
    local service="$1"
    local container
    container=$(get_container_name "$service")
    is_container_running "$container"
}

# Wait for a container to be healthy
# Usage: wait_for_health <container_name> <timeout_seconds>
wait_for_health() {
    local container="$1"
    local timeout="${2:-60}"
    local elapsed=0
    
    echo -n "Waiting for $container to be healthy"
    while [ "$elapsed" -lt "$timeout" ]; do
        local health
        health=$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null)
        
        if [ "$health" == "healthy" ]; then
            echo ""
            return 0
        fi
        
        echo -n "."
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo ""
    echo_red "Timeout waiting for $container"
    return 1
}
