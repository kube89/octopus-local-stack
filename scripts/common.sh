#!/bin/bash
# Common functions and configuration for octopus-local-stack scripts

# Determine paths
# PROJECT_DIR is always relative to common.sh location (works for nested scripts)
COMMON_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$COMMON_SH_DIR/.." && pwd)"
# SCRIPT_DIR is the caller's directory (for scripts that need their own location)
export SCRIPT_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
CONFIG_FILE="$PROJECT_DIR/octopus-local-stack.yaml"
RUNTIME_DIR="${OCTOPUS_LOCAL_STACK_RUNTIME_DIR:-/runtime}"
RUNTIME_STATE_FILE="$RUNTIME_DIR/stack.state"
export RUNTIME_CONTRACT_VERSION=1

# Colors
echo_green()  { echo -e "\033[0;32m$*\033[0m"; }
echo_yellow() { echo -e "\033[0;33m$*\033[0m"; }
echo_red()    { echo -e "\033[0;31m$*\033[0m"; }

# Load configuration from YAML
load_config() {
    local config_lines
    local key
    local value

    if [ ! -f "$CONFIG_FILE" ]; then
        echo_red "Error: Configuration file not found: $CONFIG_FILE"
        return 1
    fi

    if ! config_lines=$(yq -r '.env | to_entries[] | [.key, (.value | tostring)] | @tsv' "$CONFIG_FILE"); then
        echo_red "Error: Unable to read configuration: $CONFIG_FILE"
        return 1
    fi

    while IFS=$'\t' read -r key value; do
        [ -z "$key" ] && continue
        if [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            echo_red "Error: Invalid configuration key: $key"
            return 1
        fi
        printf -v "$key" '%s' "$value"
        export "${key?}"
    done <<< "$config_lines"
}

# Return success when any persisted Octopus Server data volume exists.
server_data_volumes_exist() {
    local volume
    for volume in \
        octopus-server_artifacts \
        octopus-server_cache \
        octopus-server_import \
        octopus-server_repository \
        octopus-server_sqlvolume \
        octopus-server_taskLogs; do
        if docker volume inspect "$volume" >/dev/null 2>&1; then
            return 0
        fi
    done
    return 1
}

generate_runtime_state() {
    local generated_state
    local temporary_state
    local previous_umask

    if server_data_volumes_exist; then
        echo_red "Error: Server data exists but its generated credential state is missing."
        echo_red "Run 'make clean' once to remove the old stack before starting it with generated credentials."
        return 1
    fi

    if ! mkdir -p "$RUNTIME_DIR"; then
        echo_red "Error: Unable to create runtime state directory: $RUNTIME_DIR"
        return 1
    fi

    if ! generated_state=$(python3 <<'PY'
import base64
import secrets
import string
import uuid

api_key_alphabet = string.ascii_uppercase + string.digits
values = {
    "INSTANCE_ID": str(uuid.uuid4()),
    "SA_PASSWORD": f"OctoDb!9{secrets.token_hex(20)}",
    "ADMIN_PASSWORD": f"OctoAdmin!9{secrets.token_hex(20)}",
    "MASTER_KEY": base64.b64encode(secrets.token_bytes(16)).decode("ascii"),
    "OCTOPUS_API_KEY": "API-" + "".join(
        secrets.choice(api_key_alphabet) for _ in range(31)
    ),
}

for key, value in values.items():
    print(f"{key}\t{value}")
PY
    ); then
        echo_red "Error: Unable to generate runtime credentials."
        return 1
    fi

    previous_umask=$(umask)
    umask 077
    temporary_state=$(mktemp "$RUNTIME_DIR/stack.state.XXXXXX") || {
        umask "$previous_umask"
        echo_red "Error: Unable to create runtime state file."
        return 1
    }

    if ! printf '%s\n' "$generated_state" > "$temporary_state"; then
        rm -f "$temporary_state"
        umask "$previous_umask"
        echo_red "Error: Unable to write runtime state."
        return 1
    fi

    if ! mv "$temporary_state" "$RUNTIME_STATE_FILE"; then
        rm -f "$temporary_state"
        umask "$previous_umask"
        echo_red "Error: Unable to store runtime state."
        return 1
    fi
    umask "$previous_umask"
}

load_runtime_state() {
    local key
    local value
    local seen_keys=""
    local required_key

    if [ ! -f "$RUNTIME_STATE_FILE" ]; then
        echo_red "Error: Generated stack credentials are unavailable."
        return 1
    fi

    unset OCTOPUS_API_KEY
    while IFS=$'\t' read -r key value; do
        [ -z "$key" ] && continue
        case "$key" in
            INSTANCE_ID|SA_PASSWORD|ADMIN_PASSWORD|MASTER_KEY|OCTOPUS_API_KEY)
                printf -v "$key" '%s' "$value"
                export "${key?}"
                seen_keys="$seen_keys $key"
                ;;
            *)
                echo_red "Error: Invalid runtime state key: $key"
                return 1
                ;;
        esac
    done < "$RUNTIME_STATE_FILE"

    for required_key in INSTANCE_ID SA_PASSWORD ADMIN_PASSWORD MASTER_KEY OCTOPUS_API_KEY; do
        case " $seen_keys " in
            *" $required_key "*) ;;
            *)
                echo_red "Error: Runtime state is missing $required_key."
                return 1
                ;;
        esac
    done

    if [[ ! "$OCTOPUS_API_KEY" =~ ^API-[A-Z0-9]{31}$ ]]; then
        echo_red "Error: Runtime state contains an invalid OCTOPUS_API_KEY."
        return 1
    fi
}

ensure_runtime_state() {
    if [ ! -f "$RUNTIME_STATE_FILE" ]; then
        generate_runtime_state || return 1
    fi
    load_runtime_state
}

clear_runtime_state() {
    if ! rm -f "$RUNTIME_STATE_FILE" "$RUNTIME_DIR"/stack.state.*; then
        echo_red "Error: Unable to remove generated stack credentials."
        return 1
    fi
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
    
    while [ "$attempt" -le "$max_attempts" ]; do
        if "$@"; then
            return 0
        fi
        echo_yellow "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..." >&2
        sleep "$delay"
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
