#!/bin/bash

# Full cleanup of Octopus Local Stack resources
# Only cleans octopus-server and octopus-tentacle - no side effects on other docker setups

# Source common functions
# Source common functions
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo ""

print_header_box "OCTOPUS LOCAL STACK - FULL CLEANUP"

function remove_server_stack {
    echo "--- Removing Octopus Server ---"
    pushd "$PROJECT_DIR/docker/octopus-server" >/dev/null 2>&1 && {
        docker compose down --volumes --remove-orphans 2>/dev/null || true
        popd >/dev/null
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
                popd >/dev/null
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

    # Octopus server volumes
    for pattern in "octopus-server_" "sqlvolume" "repository" "artifacts" "taskLogs" "cache" "import"; do
        docker volume ls -q --filter "name=$pattern" 2>/dev/null | while read -r vol; do
            echo "  Removing volume: $vol"
            docker volume rm "$vol" 2>/dev/null || true
        done
    done

    # Tentacle volumes
    docker volume ls -q --filter "name=tentacle" 2>/dev/null | while read -r vol; do
        echo "  Removing volume: $vol"
        docker volume rm "$vol" 2>/dev/null || true
    done

    echo_green "✓ Volumes cleaned"
}

function remove_images {
    echo ""
    echo "--- Removing Images ---"

    # Remove built images (cli, tentacle)
    for pattern in "octopus-local-stack" "octopus-tentacle"; do
        docker images --format "{{.Repository}}:{{.Tag}}" | grep "$pattern" | while read -r img; do
            echo "  Removing image: $img"
            docker rmi "$img" 2>/dev/null || true
        done
    done

    # Remove base images (optional - they take time to re-download)
    for img in "octopusdeploy/octopusdeploy:latest" "octopusdeploy/tentacle:latest" "mcr.microsoft.com/mssql/server:latest"; do
        if docker images -q "$img" 2>/dev/null | grep -q .; then
            echo "  Removing base image: $img"
            docker rmi "$img" 2>/dev/null || true
        fi
    done

    # Prune dangling images
    echo "  Pruning dangling images..."
    docker image prune -f 2>/dev/null || true

    echo_green "✓ Images cleaned"
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
        echo "$networks" | sed 's/^/  /'
    fi
}

# --- Main Execution Flow ---
remove_server_stack
remove_tentacles
remove_volumes
remove_images
remove_networks
print_summary
