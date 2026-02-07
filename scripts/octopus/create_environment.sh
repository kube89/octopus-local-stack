#!/bin/bash

# Creates an Octopus Deploy environment via API
# Usage: create_environment.sh <name> [description]

# Source common functions
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
source "$(dirname "${BASH_SOURCE[0]}")/api.sh"
load_config

NAME="${1:-}"
DESCRIPTION="${2:-}"

if [ -z "$NAME" ]; then
    echo_red "Error: Environment name is required"
    echo "Usage: create_environment.sh <name> [description]"
    exit 1
fi

create_environment "$NAME" "$DESCRIPTION"
