#!/bin/bash

# Source common functions and helpers
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/docker/compose.sh"
source "$(dirname "${BASH_SOURCE[0]}")/octopus/api.sh"

function usage() {
  cat <<'EOF' >&2
Usage: manage_octopus_server.sh [command]

Commands:
  up       Start the local stack (Server + DB)
  down     Stop the local stack
  status   Show status of stack and tentacles

Examples:
  ./manage_octopus_server.sh up           # Start server stack
  ./manage_octopus_server.sh down         # Stop server stack
EOF
}

# Check for registered tentacles and log status
function show_status {
	echo "Checking status..."
    # Validate the startup-provisioned API key before showing status.
    if is_service_running "octopus-server"; then
        if ! is_api_key_valid; then
            echo_red "Error: The generated Octopus API key is not valid."
            echo_red "Run 'make clean' to recreate this disposable stack and its credentials."
            return 1
        fi
    fi

    # Display Server Status Box
	local box_width=60
	local label_width=12
	local value_width=$((box_width - label_width - 4))
	print_box_row() { printf "\033[0;33m║  %-${label_width}s %-${value_width}s ║\033[0m\n" "$1" "$2"; }
	
	echo ""
	echo_yellow "╔$(printf '═%.0s' $(seq 1 $box_width))╗"
	echo_yellow "║$(printf ' %.0s' $(seq 1 20))OCTOPUS SERVER READY$(printf ' %.0s' $(seq 1 20))║"
	echo_yellow "╠$(printf '═%.0s' $(seq 1 $box_width))╣"
	print_box_row "URL:" "$OCTOPUS_URL"
	print_box_row "Username:" "$ADMIN_USERNAME"
	print_box_row "Credentials:" "available via make connection-json"
	echo_yellow "╚$(printf '═%.0s' $(seq 1 $box_width))╝"
	echo ""

    local machines
    local workers
    local count=0
    local m_count=0
    local w_count=0
    
    # 1. Deployment Targets
    if machines=$(list_machines 2>/dev/null); then
        m_count=$(echo "$machines" | jq length)
        count=$((count + m_count))
    fi

    # 2. Workers
    if workers=$(list_workers 2>/dev/null); then
         w_count=$(echo "$workers" | jq length)
         count=$((count + w_count))
    fi
    
    if [ "$count" -eq 0 ]; then
        echo_yellow "Stack is up, but no tentacles registered."
        echo "Run './scripts/manage_tentacles.sh up ...' or use the menu to add one."
    else
        echo_green "Registered Tentacles ($count):"
        
        # Display Deployment Targets
        if [ "$m_count" -gt 0 ]; then
             echo "$machines" | jq -r '.[] | " - \(.Name) [\( (.Roles // ["worker"]) | join(",") )] (\(.HealthStatus // .Status // "Unknown"))"'
        fi
        
        # Display Workers
        if [ "$w_count" -gt 0 ]; then
             # Workers have "WorkerPools" (array) usually, not Roles
             echo "$workers" | jq -r '.[] | " - \(.Name) [Worker] (\(.HealthStatus // .Status // "Unknown"))"'
        fi
    fi
}

function stop_server {
    local ids
    local name

    pushd "$PROJECT_DIR/docker/octopus-server" >/dev/null || return 1
	echo "Stopping Octopus Server stack..."

    # Deregister all tentacles via API first
    echo "Deregistering all tentacles..."
    if machines=$(list_machines 2>/dev/null); then
        ids=$(echo "$machines" | jq -r '.[].Id')
        for id in $ids; do
            name=$(echo "$machines" | jq -r ".[] | select(.Id==\"$id\") | .Name")
            echo "  Removing Deployment Target: $name ($id)"
            delete_machine "$id" || echo_yellow "  Warning: Failed to delete $id"
        done
    fi
    # Also workers
    if workers=$(list_workers 2>/dev/null); then
        ids=$(echo "$workers" | jq -r '.[].Id')
        for id in $ids; do
             name=$(echo "$workers" | jq -r ".[] | select(.Id==\"$id\") | .Name")
             echo "  Removing Worker: $name ($id)"
             delete_worker "$id" || echo_yellow "  Warning: Failed to delete $id"
        done
    fi

    # Use 'delete-all' from manage_tentacles which stops AND removes
    echo "Removing tentacle containers..."
    bash "$SCRIPT_DIR/manage_tentacles.sh" delete-all || true

	docker compose down
    popd >/dev/null || return 1
    echo_green "✓ Stack stopped."
}

function start_server {
    local db_container
    local web_container

    pushd "$PROJECT_DIR/docker/octopus-server" >/dev/null || return 1

	# Check if octopus server is already running
    if is_service_running "octopus-server"; then
        echo_green "Octopus Server is already running."
        show_status
		popd >/dev/null || return 1
		return 0
	fi

    echo "Starting Octopus Server..."
    if ! check_ports_available; then
        popd >/dev/null || return 1
        return 1
    fi
    
    if ! docker compose up -d db octopus-server; then
        popd >/dev/null || return 1
        return 1
    fi
    
    # Monitor startup - wait for API or early exit on container failure
    echo "Waiting for Octopus Server to be ready (this may take a few minutes)..."
    local timeout=300
    local start_time=$SECONDS
    
    while true; do
        # Check if API is ready (borrowed check from api.sh but simpler curl)
        if curl -fsS "${OCTOPUS_INTERNAL_URL}/api/octopusservernodes/ping" >/dev/null 2>&1; then
            echo ""
            break
        fi
        
        # Check if containers are still running
        if ! is_service_running "octopus-server" || ! is_service_running "db"; then
            echo ""
            echo_red "Error: Octopus Server or Database container stopped unexpectedly!"
            
            # Show logs for diagnosis
            db_container=$(get_container_name "db")
            web_container=$(get_container_name "octopus-server")
            
            if [ -n "$db_container" ]; then
                echo_yellow "--- Logs for $db_container ---"
                docker logs "$db_container" 2>&1 | tail -n 20
            fi
            
            if [ -n "$web_container" ]; then
                echo_yellow "--- Logs for $web_container ---"
                docker logs "$web_container" 2>&1 | tail -n 20
            fi
            
            popd >/dev/null || return 1
            return 1
        fi
        
        # Timeout check
        if (( SECONDS - start_time > timeout )); then
            echo ""
            echo_red "Timeout waiting for Octopus API"
            popd >/dev/null || return 1
            return 1
        fi
        
        echo -n "."
        sleep 5
    done
    
    echo "Validating startup-provisioned API key..."
    if ! retry_curl curl -fsS -o /dev/null \
        -H "X-Octopus-ApiKey: $OCTOPUS_API_KEY" \
        "${OCTOPUS_INTERNAL_URL%/}/api/users/me"; then
        echo_red "Error: Octopus did not accept the generated API key."
        popd >/dev/null || return 1
        return 1
    fi

    show_status || {
        popd >/dev/null || return 1
        return 1
    }
    popd >/dev/null || return 1
}

function check_ports_available() {
    check_port 8080 "Web Portal" || return 1
    check_port 1401 "SQL Server" || return 1
    check_port 11111 "Tentacles" || return 1
    check_port 8443 "gRPC" || return 1
}

# Default settings
COMMAND=""

# Parse args
for arg in "$@"; do
  case $arg in
    up|down|status)
      COMMAND=$arg
      ;;
    usage|help|--help|-h)
      usage
      exit 0
      ;;
  esac
done

if [ -z "$COMMAND" ]; then
    usage
    exit 1
fi

case "$COMMAND" in
  up)
    check_dependencies || exit 1
    load_config || exit 1
    ensure_runtime_state || exit 1
    start_server || exit 1
    ;;
  down)
    check_dependencies || exit 1
    load_config || exit 1
    load_runtime_state || exit 1
    stop_server || exit 1
    ;;
  status)
    check_dependencies || exit 1
    load_config || exit 1
    load_runtime_state || exit 1
    # Show connection info if up - READ ONLY CHECK
    if is_service_running "octopus-server"; then
        show_status
    else
        echo "Octopus Server is NOT running."
    fi
    ;;

  *)
    echo "Unknown command: $COMMAND"
    usage
    exit 1
    ;;
esac
