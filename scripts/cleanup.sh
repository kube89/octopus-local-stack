#!/bin/bash

# Full cleanup of Octopus Local Stack resources
# Only cleans octopus-server and octopus-tentacle - no side effects on other docker setups

# Source common functions
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo ""

print_header_box "OCTOPUS LOCAL STACK - FULL CLEANUP"

function remove_server_stack {
    echo "--- Removing Octopus Server ---"
    pushd "$PROJECT_DIR/docker/octopus-server" >/dev/null 2>&1 && {
        docker compose down --volumes --remove-orphans 2>/dev/null || true
        popd >/dev/null || return 1
    }

    # Also catch any orphaned octopus-server containers
    docker ps -a --filter "name=octopus-server" --format "{{.Names}}" | while read -r container; do
        echo "  Removing container: $container"
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    done
    echo_green "✓ Octopus Server containers cleaned"
}

function remove_tentacles {
    echo ""
    echo "--- Removing Tentacles ---"

    # Iterate over all possible OS folders
    for os_dir in "$PROJECT_DIR/docker/tentacles"/*; do
        if [ -d "$os_dir" ]; then
            pushd "$os_dir" >/dev/null 2>&1 && {
                docker compose down --volumes --remove-orphans 2>/dev/null || true
                popd >/dev/null || return 1
            }
        fi
    done

    # Catch any orphaned tentacle containers (pattern: tentacle-* or octopus-tentacle-*)
    docker ps -a --filter "name=tentacle" --format "{{.Names}}" | while read -r container; do
        echo "  Removing container: $container"
        docker stop "$container" 2>/dev/null || true
        docker rm "$container" 2>/dev/null || true
    done
    echo_green "✓ Tentacle containers cleaned"
}

function remove_volumes {
    echo ""
    echo "--- Removing Volumes ---"

    for vol in \
        octopus-server_artifacts \
        octopus-server_cache \
        octopus-server_import \
        octopus-server_repository \
        octopus-server_sqlvolume \
        octopus-server_taskLogs; do
        if docker volume inspect "$vol" >/dev/null 2>&1; then
            echo "  Removing volume: $vol"
            docker volume rm "$vol" 2>/dev/null || true
        fi
    done

    docker volume ls --format '{{.Name}}' 2>/dev/null | while read -r vol; do
        case "$vol" in
            octopus-tentacle-*_tentacle-data)
                echo "  Removing volume: $vol"
                docker volume rm "$vol" 2>/dev/null || true
                ;;
        esac
    done

    echo_green "✓ Volumes cleaned"
}

function remove_networks {
    echo ""
    echo "--- Removing Networks ---"
    for pattern in "octopus-server" "octopus-tentacle"; do
        docker network ls -q --filter "name=$pattern" 2>/dev/null | while read -r net; do
            echo "  Removing network: $net"
            docker network rm "$net" 2>/dev/null || true
        done
    done
    echo_green "✓ Networks cleaned"
}

function print_summary {
    print_header_box "CLEANUP COMPLETE"
    echo ""
    echo "Remaining Docker resources:"
    echo ""
    echo "Containers:"
    containers=$(docker ps -a --format "  {{.Names}}" 2>/dev/null)
    if [ -z "$containers" ]; then
        echo "  (none)"
    else
        echo "$containers"
    fi
    echo ""
    echo "Images:"
    images=$(docker images --format "  {{.Repository}}:{{.Tag}}" 2>/dev/null)
    if [ -z "$images" ]; then
        echo "  (none)"
    else
        echo "$images"
    fi
    echo ""
    echo "Volumes:"
    volumes=$(docker volume ls --format "  {{.Name}}" 2>/dev/null)
    if [ -z "$volumes" ]; then
        echo "  (none)"
    else
        echo "$volumes"
    fi
    echo ""
    echo "Networks:"
    networks=$(docker network ls --format "{{.Name}}" 2>/dev/null | grep -v -E "^(bridge|host|none)$")
    if [ -z "$networks" ]; then
        echo "  (none)"
    else
        printf '%s\n' "$networks" | awk '{ print "  " $0 }'
    fi
}

# --- Main Execution Flow ---
remove_server_stack
remove_tentacles
remove_volumes
remove_networks

if server_data_volumes_exist; then
    echo_red "Error: Server data volumes remain, so generated credentials were preserved."
    print_summary
    exit 1
fi

clear_runtime_state || exit 1
print_summary
