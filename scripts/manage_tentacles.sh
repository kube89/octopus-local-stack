#!/bin/bash

# Tentacle management script
# Usage: register_tentacle.sh <command> <name> <environment> <role>

# Source common functions
# Source common functions
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/docker/compose.sh"
source "$(dirname "${BASH_SOURCE[0]}")/octopus/api.sh"
load_config || exit 1
load_runtime_state || exit 1

TENTACLE_OS="linux"

# Parse optional arguments
# Usage: ./manage_tentacles.sh command [name] [env] [role] [--os <os>] [--config <file>]
# Parse optional arguments
# Usage: ./manage_tentacles.sh command [name] [env] [role] [--os <os>] [--config <file>] [--type <target|worker>] [--worker-pool <pool>]
CONFIG_FILE_PATH=""
AUTO_CREATE_ENV=false
TENTACLE_TYPE="target"
WORKER_POOL=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --os) TENTACLE_OS="$2"; shift ;;
        --config) CONFIG_FILE_PATH="$2"; shift ;;
        --create-env) AUTO_CREATE_ENV=true ;;
        --type) TENTACLE_TYPE="$2"; shift ;;
        --worker-pool) WORKER_POOL="$2"; shift ;;
        *) POSITIONALS+=("$1") ;;
    esac
    shift
done

set -- "${POSITIONALS[@]}"
COMMAND="${1:-}"
NAME="${2:-}"
ENVIRONMENT="${3:-}"
ROLE="${4:-}"

TENTACLE_DIR="$PROJECT_DIR/docker/tentacles/$TENTACLE_OS"
if [ ! -d "$TENTACLE_DIR" ]; then
    echo_red "Error: OS '$TENTACLE_OS' not supported (directory $TENTACLE_DIR not found)"
    exit 1
fi

function usage {
    cat <<'EOF'
Usage: manage_tentacles.sh <command> [name] [environment] [role] [--os <os>] [--config <file>]

Commands:
  up       Start tentacle(s)
  down     Stop tentacle
  clean    Stop tentacle and remove volumes
  delete-all Deregister and remove ALL tentacles (Factory Reset for Tentacles)
  logs     Show tentacle logs

Arguments:
  name         Tentacle name (required for up unless --config is used)
  environment  Target environment (default: Test)
  role         Target role (default: same as name)
  --config     Path to YAML config file (for bulk registration)
  --os         OS type (default: linux)
  --create-env Auto-create environment if missing (default: prompt)
  --type       Tentacle type: 'target' (default) or 'worker'
  --worker-pool Worker Pool name (required if type is worker)

Examples:
  ./manage_tentacles.sh up tentacle-web Test web-server
  ./manage_tentacles.sh up --config tentacles.yaml
  ./manage_tentacles.sh up worker-1 --type worker --worker-pool "Default Worker Pool"
  ./manage_tentacles.sh down tentacle-web
  ./manage_tentacles.sh delete-all
EOF
}

function wait_for_container {
    local container_name="$1"
    echo "Waiting for $container_name to start..."
    local timeout=60
    local elapsed=0
    local interval=2
    
    while [ $elapsed -lt $timeout ]; do
        if docker logs "$container_name" 2>&1 | grep -q -E 'Listening for connections|Agent will poll'; then
            echo_green "$container_name is ready."
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done

    echo ""
    echo_red "Timed out waiting for $container_name."
    docker logs "$container_name"
    return 1
}

# Wrapper to check environment and list if missing
function ensure_environment_exists {
    local env_name="$1"
    echo "Checking if environment '$env_name' exists..."
    
    if check_environment_exists "$env_name"; then
        echo_green "✓ Environment '$env_name' exists"
        return 0
    fi
    
    echo_red "Environment '$env_name' does not exist."
    
    # If --create-env flag is present, create and proceed
    if [ "$AUTO_CREATE_ENV" = true ]; then
        echo "Auto-creating environment '$env_name'..."
        create_environment "$env_name"
        return 0
    fi

    # Prompt for creation if in interactive mode (stdin is tty)
    if [ -t 0 ]; then
        read -p "Create environment '$env_name' now? (y/n): " -r CONFIRM
        if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
            create_environment "$env_name"
            return 0
        fi
    fi

    echo "Available environments:"
    octopus_api_call "GET" "environments" | jq -r '.Items[].Name' 2>/dev/null || echo "  (unable to list)"
    return 1
}

function start_tentacle {
    local name="$1"
    local environment="${2:-Test}"
    local role="${3:-$name}"
    
    if [ -z "$name" ]; then
        echo_red "Error: Tentacle name is required"
        usage
        exit 1
    fi
    
    # Check for existing container
    local container_name="tentacle-$name"
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        echo_yellow "Container '$container_name' already exists"
        if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
            echo_green "Tentacle '$name' is already running"
            return 0
        else
            echo "Removing stopped container..."
            docker rm "$container_name" >/dev/null
        fi
    fi
    
    # Check environment exists before proceeding
    if ! ensure_environment_exists "$environment"; then
        exit 1
    fi
    
    echo "--- Starting Tentacle: $name ---"
    
    if [ "$TENTACLE_TYPE" == "worker" ]; then
        if [ -z "$WORKER_POOL" ]; then
            # If from config, this might be separate, but for CLI arguments:
            # We need to ensure we have a worker pool.
            # If function called from create_from_config, WORKER_POOL needs to be set there.
            echo_red "Error: --worker-pool is required for type 'worker'"
            exit 1
        fi
        echo "  Type: Worker"
        echo "  Pool: $WORKER_POOL"
        
        export OCTOPUS_TARGET_WORKER_POOL="$WORKER_POOL"
        export OCTOPUS_TARGET_ENVIRONMENT=""
        export OCTOPUS_TARGET_ROLE=""
    else
        echo "  Type: Deployment Target"
        echo "  Environment: $environment"
        echo "  Role: $role"

        export OCTOPUS_TARGET_ENVIRONMENT="$environment"
        export OCTOPUS_TARGET_ROLE="$role"
        export OCTOPUS_TARGET_WORKER_POOL=""
    fi
     
    pushd "$TENTACLE_DIR" >/dev/null || return 1
    
    export OCTOPUS_TARGET_NAME="$name"
    
    echo "Building and starting $name..."
    if ! docker compose up -d --build tentacle 2>&1; then
        echo ""
        echo_red "ERROR: Failed to start $name"
        popd >/dev/null || return 1
        return 1
    fi
    
    # Wait for container by name
    local container_name="tentacle-$name"
    if ! wait_for_container "$container_name"; then
        echo ""
        echo_red "ERROR: $name failed to start"
        popd >/dev/null || return 1
        return 1
    fi
    
    popd >/dev/null || return 1
}

function stop_tentacle {
    local name="$1"
    local machines_json
    local workers_json
    local id
    
    echo "--- Stopping Tentacle${name:+: $name} ---"
    pushd "$TENTACLE_DIR" >/dev/null || return 1
    
    if [ -n "$name" ]; then
        # Deregister first
        # Try finding in Machines (Targets)
        machines_json=$(list_machines 2>/dev/null)
        id=$(echo "$machines_json" | jq -r ".[] | select(.Name == \"$name\") | .Id")
        
        if [ -n "$id" ] && [ "$id" != "null" ]; then
             echo "Deregistering Deployment Target $name ($id)..."
             delete_machine "$id"
        else
             # Try finding in Workers
             workers_json=$(list_workers 2>/dev/null)
             id=$(echo "$workers_json" | jq -r ".[] | select(.Name == \"$name\") | .Id")
             
             if [ -n "$id" ] && [ "$id" != "null" ]; then
                 echo "Deregistering Worker $name ($id)..."
                 delete_worker "$id"
             fi
        fi

        export OCTOPUS_TARGET_NAME="$name"
        docker compose stop "$name" 2>/dev/null || true
        docker compose rm -f "$name" 2>/dev/null || true
    else
        echo_yellow "No name provided. Stopping all tentacle containers..."
        docker ps -a --filter "name=octopus-tentacle" --format "{{.Names}}" | xargs -r docker stop 2>/dev/null || true
        docker ps -a --filter "name=octopus-tentacle" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null || true
    fi
    
    popd >/dev/null || return 1
}

function delete_all {
    local ids
    local name

    # Deregister Deployment Targets
    if machines=$(list_machines 2>/dev/null); then
        ids=$(echo "$machines" | jq -r '.[].Id')
        for id in $ids; do
            name=$(echo "$machines" | jq -r ".[] | select(.Id==\"$id\") | .Name")
            echo "Deregistering Deployment Target: $name ($id)"
            delete_machine "$id" || echo_yellow "Warning: Failed to deregister $name"
        done
    fi

    # Deregister Workers
    if workers=$(list_workers 2>/dev/null); then
        ids=$(echo "$workers" | jq -r '.[].Id')
        for id in $ids; do
             name=$(echo "$workers" | jq -r ".[] | select(.Id==\"$id\") | .Name")
             echo "Deregistering Worker: $name ($id)"
             delete_worker "$id" || echo_yellow "Warning: Failed to deregister $name"
        done
    fi
    
    # Remove Tentacle Containers and Volumes
    echo "Removing all Tentacle containers..."
    docker ps -a --filter "name=octopus-tentacle" --format "{{.Names}}" | xargs -r docker stop 2>/dev/null
    docker ps -a --filter "name=octopus-tentacle" --format "{{.Names}}" | xargs -r docker rm -f 2>/dev/null
    
    echo "Removing all Tentacle volumes..."
    docker volume ls --filter "name=tentacle" -q | xargs -r docker volume rm 2>/dev/null
    
    echo_green "✓ All tentacles removed."
}

function delete_tentacle {
    local name="$1"
    
    echo "--- Deleting Tentacle${name:+: $name} ---"
    pushd "$TENTACLE_DIR" >/dev/null || return 1
    
    if [ -n "$name" ]; then
        export OCTOPUS_TARGET_NAME="$name"
        docker compose down --volumes --remove-orphans 2>/dev/null || true
    else
        # Remove all tentacle containers and volumes
        docker ps -a --filter "name=octopus-tentacle" --format "{{.Names}}" | xargs -r docker stop 2>/dev/null || true
        docker ps -a --filter "name=octopus-tentacle" --format "{{.Names}}" | xargs -r docker rm 2>/dev/null || true
        docker volume ls --filter "name=tentacle" -q | xargs -r docker volume rm 2>/dev/null || true
    fi
    
    popd >/dev/null || return 1
}

function show_logs {
    local name="$1"
    
    pushd "$TENTACLE_DIR" >/dev/null || return 1
    
    if [ -n "$name" ]; then
        export OCTOPUS_TARGET_NAME="$name"
        docker compose logs "$name"
    else
        # Show logs for all tentacle containers
        docker ps -a --filter "name=octopus-tentacle" --format "{{.Names}}" | while read -r container; do
            echo "Logs for $container"
            docker logs "$container" 2>&1 | tail -50
        done
    fi
    
    popd >/dev/null || return 1
}

function create_from_config {
    local config_file="$1"
    echo "Processing config file: $config_file"
    
    if [ ! -f "$config_file" ]; then
        echo_red "Error: Config file '$config_file' not found"
        exit 1
    fi
    
    # Check if yq is available (should be from common.sh/CLI)
    if ! command -v yq >/dev/null; then
        echo_red "Error: yq is required for processing YAML files"
        exit 1
    fi
    
    # Read tentacles array length
    local count
    count=$(yq '.tentacles | length' "$config_file")
    
    if [ "$count" -eq 0 ]; then
        echo_yellow "No tentacles found in config file."
        exit 0
    fi
    
    echo "Found $count tentacles in config."
    
    # Loop through items
    for ((i=0; i<count; i++)); do
        # Extract fields
        local t_name t_env t_role t_os t_type t_pool
        t_name=$(yq ".tentacles[$i].name" "$config_file")
        t_env=$(yq ".tentacles[$i].environment // \"Test\"" "$config_file")
        t_role=$(yq ".tentacles[$i].role // \"$t_name\"" "$config_file")
        t_os=$(yq ".tentacles[$i].os // \"linux\"" "$config_file")
        t_type=$(yq ".tentacles[$i].type // \"target\"" "$config_file")
        t_pool=$(yq ".tentacles[$i].worker_pool // \"Default Worker Pool\"" "$config_file")
        
        # Check if OS is supported
        local derived_dir="$PROJECT_DIR/docker/tentacles/$t_os"
        if [ ! -d "$derived_dir" ]; then
             echo_red "Skipping $t_name: OS '$t_os' not supported"
             continue
        fi
        
        echo ""
        echo "Processing [$((i+1))/$count]: $t_name ($t_os) [$t_type]"
        
        TENTACLE_DIR="$derived_dir"
        TENTACLE_TYPE="$t_type"
        WORKER_POOL="$t_pool"
        
        start_tentacle "$t_name" "$t_env" "$t_role"
    done
}


case "$COMMAND" in
  up|start)
    # Pre-flight check: Is server running and healthy?
    if ! is_service_running "octopus-server"; then
        echo_red "Error: Octopus Server container is not running."
        echo "Please start the stack first: ./manage_octopus_server.sh up or select 'Start Stack' in the menu."
        exit 1
    fi
    
    # Check API health (fast ping)
    if ! curl -fsS --max-time 2 "${OCTOPUS_INTERNAL_URL}/api/octopusservernodes/ping" >/dev/null 2>&1; then
        echo_red "Error: Octopus Server container is running, but API is not reachable."
        echo "The server might be starting up or unhealthy."
        echo "Check logs: docker logs octopus-server"
        exit 1
    fi

    if [ -n "$CONFIG_FILE_PATH" ]; then
        create_from_config "$CONFIG_FILE_PATH"
    else
        start_tentacle "$NAME" "$ENVIRONMENT" "$ROLE"
    fi
    ;;
  down|stop)
    stop_tentacle "$NAME"
    ;;
  delete-all)
    delete_all
    ;;
  clean)
    delete_tentacle "$NAME"
    ;;
  logs)
    show_logs "$NAME"
    ;;
  *)
    usage
    exit 1
    ;;
esac
