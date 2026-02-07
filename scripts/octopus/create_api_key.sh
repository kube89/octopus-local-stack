#!/bin/bash

# Seeds the ApiKey table with a pre-hashed API key
# This allows the same API key to work across fresh Octopus instances

# Source common functions
source "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
load_config

# DB connection settings
DB_CONTAINER="octopus-server-db-1"
DB_PASSWORD="$SA_PASSWORD"
DB_NAME="OctopusDeploy"

# Verify container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${DB_CONTAINER}$"; then
    echo -e "${RED}Error: Container '$DB_CONTAINER' is not running${NC}"
    exit 1
fi

# Pre-defined API key values (static - these don't change)
API_KEY_ID="apikeys-WjUvpxvRnb7d4Y3KoME1B73PA"
API_KEY_HASHED="PBKDF2-SHA256\$3E8\$IcRfcgGrNz6xKXixBt0zGA==\$Hx5a+ss5SjRvrJ3ZJNBF8/S0JPVfo+fR7ec13cMxGlA="
API_KEY_PURPOSE="octopus-local-stack"
API_KEY_HINT="API-2QEH"

# Run SQL command
run_sql() {
    local query="$1"
    echo "$query" \
        | docker exec -i "$DB_CONTAINER" \
            /opt/mssql-tools18/bin/sqlcmd \
            -S localhost \
            -U sa \
            -P "$DB_PASSWORD" \
            -C \
            -d "$DB_NAME"
}

# Run SQL query and return JSON
run_sql_json() {
    local query="$1"
    echo "$query" \
        | docker exec -i "$DB_CONTAINER" \
            /opt/mssql-tools18/bin/sqlcmd \
            -S localhost \
            -U sa \
            -P "$DB_PASSWORD" \
            -C \
            -d "$DB_NAME" \
            -s"," \
            -W \
        | awk -F',' '
            NR==1 { for(i=1;i<=NF;i++) header[i]=$i; next }
            /^-+/ { next }
            /rows affected/ { next }
            /^$/ { next }
            {
                printf "{"
                for(i=1;i<=NF;i++) {
                    gsub(/"/, "\\\"", $i)
                    printf "\"%s\":\"%s\"", header[i], $i
                    if(i<NF) printf ","
                }
                print "}"
            }
        ' \
        | jq -s .
}

# Print ApiKey table as JSON
print_api_key_table() {
    echo "ApiKey table:"
    run_sql_json "SELECT Id, UserId, ApiKeyHashed, Created, Expires, Purpose, ApiKeyHint FROM ApiKey;
GO"
}

# Get user ID from User table based on ADMIN_USERNAME
get_user_id() {
    local username="$ADMIN_USERNAME"
    local result
    result=$(run_sql "SELECT Id FROM [User] WHERE Username = '$username';
GO" | grep -E "^Users-" | tr -d ' ')
    
    if [ -z "$result" ]; then
        echo -e "${RED}Error: User '$username' not found in database${NC}"
        exit 1
    fi
    echo "$result"
}

# Check if API key already exists
check_exists() {
    local result
    result=$(run_sql "SELECT COUNT(*) FROM ApiKey WHERE Id = '$API_KEY_ID';
GO" | grep -E "^\s*[0-9]+" | tr -d ' ')
    
    if [ "$result" -gt 0 ]; then
        return 0  # exists
    else
        return 1  # does not exist
    fi
}

# Wait for database to be ready
wait_for_database() {
    echo "Waiting for database..."
    local timeout=60
    local elapsed=0
    
    while [ $elapsed -lt $timeout ]; do
        if echo "SELECT 1" | docker exec -i "$DB_CONTAINER" \
            /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$DB_PASSWORD" -C -d "$DB_NAME" >/dev/null 2>&1; then
            echo_green "Database is ready"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -n "."
    done
    
    echo_red "Database connection timeout"
    return 1
}

# Insert or update the API key
insert_or_update_api_key() {
    # Look up user ID dynamically
    local API_KEY_USER_ID
    API_KEY_USER_ID=$(get_user_id)
    if check_exists; then
        echo "API Key already exists, updating timestamps..."
        run_sql "
UPDATE ApiKey 
SET Created = GETUTCDATE(), 
    Expires = DATEADD(YEAR, 1, GETUTCDATE()), 
    LastModified = GETUTCDATE() 
WHERE Id = '$API_KEY_ID';
GO" > /dev/null
        echo -e "${GREEN}✓ API Key Updated${NC}"
    else
        echo "Inserting new API Key..."
        run_sql "
INSERT INTO ApiKey (Id, UserId, ApiKeyHashed, Created, Expires, ExpirationWarning, Purpose, ApiKeyHint, LastModified)
VALUES (
    '$API_KEY_ID',
    '$API_KEY_USER_ID',
    '$API_KEY_HASHED',
    GETUTCDATE(),
    DATEADD(YEAR, 1, GETUTCDATE()),
    'None',
    '$API_KEY_PURPOSE',
    '$API_KEY_HINT',
    GETUTCDATE()
);
GO"
        echo -e "${GREEN}✓ API Key Created${NC}"
    fi

    echo ""
    echo "API Key: $OCTOPUS_API_KEY"
}

# Validate the API key works
validate_api_key() {
    echo "Validating API Key against Octopus API..."
    
    if retry_curl curl -fsS -o /dev/null \
        -H "X-Octopus-ApiKey: $OCTOPUS_API_KEY" \
        "$OCTOPUS_INTERNAL_URL/api/users/me"; then
        echo -e "${GREEN}✓ API Key ($OCTOPUS_API_KEY) works${NC}"
        return 0
    else
        echo -e "${RED}✗ API Key validation failed${NC}"
        return 1
    fi
}

# Main
wait_for_database || exit 1
insert_or_update_api_key
print_api_key_table
validate_api_key