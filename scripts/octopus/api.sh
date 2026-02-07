#!/bin/bash

# Octopus Deploy API helper functions
# Depends on common.sh and load_config being called

# Make a request to the Octopus API
# Usage: octopus_api_call <method> <path> [data]
# Returns: JSON response Body (on success) or exits with error
octopus_api_call() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    
    # Ensure URL doesn't double-slash
    local url="${OCTOPUS_INTERNAL_URL%/}/api/${path#/}"
    
    local curl_cmd=(curl -fsS -X "$method" -H "X-Octopus-ApiKey: $OCTOPUS_API_KEY" -H "Content-Type: application/json")
    
    if [ -n "$data" ]; then
        curl_cmd+=(-d "$data")
    fi
    curl_cmd+=("$url")
    
    # Use retry_curl from common.sh
    if ! response=$(retry_curl "${curl_cmd[@]}"); then
         echo_red "Error: API call failed: $method $path" >&2
         return 1
    fi
    echo "$response"
}

# Check if the current API key works
is_api_key_valid() {
    # Check /api/users/me which requires valid auth
    # We use quiet curl to output nothing but return code
    curl -fsS -o /dev/null -H "X-Octopus-ApiKey: $OCTOPUS_API_KEY" "${OCTOPUS_INTERNAL_URL%/}/api/users/me" >/dev/null 2>&1
}

# Check if Octopus Server is ready
wait_for_octopus_server() {
    local timeout="${1:-300}"
    local start_time=$SECONDS
    
    echo -n "Waiting for Octopus Server to be ready"
    while true; do
        if curl -fsS "${OCTOPUS_INTERNAL_URL}/api/octopusservernodes/ping" >/dev/null 2>&1; then
            echo ""
            return 0
        fi
        
        if (( SECONDS - start_time > timeout )); then
            echo ""
            echo_red "Timeout waiting for Octopus API"
            return 1
        fi
        
        echo -n "."
        sleep 5
    done
}

# Check if an environment exists by Name
check_environment_exists() {
    local env_name="$1"
    local response
    
    response=$(octopus_api_call "GET" "environments?name=$(urlencode "$env_name")") || return 1
    
    # Check if TotalResults > 0
    local count
    count=$(echo "$response" | jq -r '.TotalResults // 0')
    
    if [ "$count" -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

# Get Environment ID by Name
get_environment_id() {
    local env_name="$1"
    local response
    
    response=$(octopus_api_call "GET" "environments?name=$(urlencode "$env_name")") || return 1
    echo "$response" | jq -r '.Items[0].Id // empty'
}

# Create an Environment
create_environment() {
    local name="$1"
    local desc="${2:-Created via Local Stack}"
    
    if check_environment_exists "$name"; then
        echo_yellow "Environment '$name' already exists"
        return 0
    fi
    
    local payload
    payload=$(jq -n --arg n "$name" --arg d "$desc" '{Name: $n, Description: $d, UseGuidedFailure: false, AllowDynamicInfrastructure: true}')
    
    local response
    response=$(octopus_api_call "POST" "environments" "$payload") || return 1
    echo_green "✓ Environment '$name' created"
}

# Helper to URL encode (simple version for names)
urlencode() {
    jq -rn --arg x "$1" '$x|@uri'
}

# List all Machines (Tentacles)
list_machines() {
    octopus_api_call "GET" "machines/all"
}

# Delete a Machine by ID
# Usage: delete_machine <machine_id>
delete_machine() {
    local id="$1"
    octopus_api_call "DELETE" "machines/$id" >/dev/null
}

# List all Workers (Tentacles)
list_workers() {
    octopus_api_call "GET" "workers/all"
}

# Delete a Worker by ID
# Usage: delete_worker <worker_id>
delete_worker() {
    local id="$1"
    octopus_api_call "DELETE" "workers/$id" >/dev/null
}
