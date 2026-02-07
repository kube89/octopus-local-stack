#!/bin/bash
# Common functions and configuration for octopus-local-stack scripts

# Determine paths
# PROJECT_DIR is always relative to common.sh location (works for nested scripts)
COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$COMMON_SH_DIR/.." && pwd)"
# SCRIPT_DIR is the caller's directory (for scripts that need their own location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
CONFIG_FILE="$PROJECT_DIR/octopus-local-stack.yaml"

# Colors
echo_green()  { echo -e "\033[0;32m$*\033[0m"; }
echo_yellow() { echo -e "\033[0;33m$*\033[0m"; }
echo_red()    { echo -e "\033[0;31m$*\033[0m"; }

# Color codes for printf
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Load configuration from YAML
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo_red "Error: Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    eval $(yq -r '.env | to_entries | .[] | "export \(.key)=\"\(.value)\""' "$CONFIG_FILE")
}

# Check if a command exists
check_command() {
    command -v "$1" >/dev/null 2>&1
}

# Check required dependencies
check_dependencies() {
    local missing=()
    for cmd in yq jq curl docker nc; do
        if ! check_command "$cmd"; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo_red "Missing required commands: ${missing[*]}"
        return 1
    fi

    # Docker engine reachable
    if ! docker info >/dev/null 2>&1; then
        echo_red "Docker is installed but not running."
        return 1
    fi

    # Docker Compose v2 available
    if ! docker compose version >/dev/null 2>&1; then
        echo_red "Docker Compose v2 not available."
        return 1
    fi
    
    # Required config file
    if [ ! -f "$CONFIG_FILE" ]; then
        echo_red "Missing configuration file: $CONFIG_FILE"
        return 1
    fi
}

# Check if a port is in use on the host
# Usage: check_port <port> <description>
# Returns 1 if port is in use, 0 if free
check_port() {
    local port=$1
    local description=$2
    
    # Check against host.docker.internal which resolves to host machine
    if nc -z host.docker.internal "$port" 2>/dev/null; then
        echo_red "Error: Port $port is in use. Required for: $description"
        return 1
    fi
    return 0
}

# Retry wrapper for commands (default: 3 attempts, 5s delay)
# Usage: retry_api_call <command> [args...]
retry_curl() {
    local max_attempts=${RETRY_COUNT:-5}
    local delay=${RETRY_DELAY:-3}
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if "$@"; then
            return 0
        fi
        echo_yellow "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..." >&2
        sleep $delay
        attempt=$((attempt + 1))
    done
    
    echo_red "Failed after $max_attempts attempts" >&2
    return 1
}

# Print a standardized yellow header box
# Usage: print_header_box "Your Title Here" [width]
print_header_box() {
    local title="$1"
    local width=62
    local title_len=${#title}
    
    if [ "$title_len" -ge $((width - 4)) ]; then
        width=$((title_len + 4))
    fi
    
    local padding_total=$((width - title_len))
    local padding_left=$((padding_total / 2))
    local padding_right=$((padding_total - padding_left))
    
    echo ""
    echo_yellow "╔$(printf '═%.0s' $(seq 1 $width))╗"
    echo_yellow "║$(printf '%*s' $padding_left "")""$title""$(printf '%*s' $padding_right "")║"
    echo_yellow "╚$(printf '═%.0s' $(seq 1 $width))╝"
}
