#!/bin/bash

# Emit the validated provider contract for local consumers.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/docker/compose.sh"
source "$(dirname "${BASH_SOURCE[0]}")/octopus/api.sh"

load_config >&2 || exit 1
load_runtime_state >&2 || exit 1

pushd "$PROJECT_DIR/docker/octopus-server" >/dev/null || exit 1
OCTOPUS_SERVER_CONTAINER=$(get_container_name "octopus-server")
OCTOPUS_DB_CONTAINER=$(get_container_name "db")

if ! is_container_running "$OCTOPUS_SERVER_CONTAINER" ||
    ! is_container_running "$OCTOPUS_DB_CONTAINER"; then
    popd >/dev/null || exit 1
    echo_red "Error: The Octopus stack is not running." >&2
    exit 1
fi

server_health=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$OCTOPUS_SERVER_CONTAINER" 2>/dev/null)
popd >/dev/null || exit 1

if [ "$server_health" != "healthy" ]; then
    echo_red "Error: Octopus Server is not healthy." >&2
    exit 1
fi

if ! is_api_key_valid; then
    echo_red "Error: The generated Octopus API key is not valid." >&2
    exit 1
fi

export RUNTIME_CONTRACT_VERSION
export OCTOPUS_SERVER_CONTAINER
export OCTOPUS_DB_CONTAINER

python3 <<'PY'
import json
import os
import sys

contract = {
    "schemaVersion": int(os.environ["RUNTIME_CONTRACT_VERSION"]),
    "instanceId": os.environ["INSTANCE_ID"],
    "octopus": {
        "url": os.environ["OCTOPUS_URL"],
        "apiKey": os.environ["OCTOPUS_API_KEY"],
        "spaceId": os.environ["OCTOPUS_SPACE"],
        "adminUsername": os.environ["ADMIN_USERNAME"],
        "adminPassword": os.environ["ADMIN_PASSWORD"],
    },
    "docker": {
        "serverContainer": os.environ["OCTOPUS_SERVER_CONTAINER"],
        "databaseContainer": os.environ["OCTOPUS_DB_CONTAINER"],
        "databaseName": os.environ["OCTOPUS_DB_NAME"],
        "databasePassword": os.environ["SA_PASSWORD"],
    },
}

json.dump(contract, fp=sys.stdout, separators=(",", ":"))
print()
PY
