# Octopus Local Stack

A fully containerised local Octopus Deploy development environment. Requires Docker with Compose v2 and Make. All other tooling is provided by the CLI container.

> [!NOTE] 
> This tool is strictly for **local development and testing**. It acts as a lightweight ephemeral stack and is not intended for production usage or long-lived infrastructure.

## Design Philosophy: Ephemeral Environments

This project operates under the assumption that local Octopus stacks are ephemeral by design.

*   The **Octopus Server** represents the baseline environment.
*   **Tentacles** are treated as disposable tooling for testing and experimentation.
*   When the server stack is torn down, Tentacles are intentionally removed to maintain a clean state.

This behaviour is intentional and sets the expectation that persistent Tentacles are explicitly out of scope.

### Data Lifecycle

- `make down` stops the server and database, removes Tentacles, and preserves server data and its matching generated credentials in Docker-managed storage.
- `make clean` removes the server and Tentacle containers and data volumes, then erases the generated credentials. Downloaded Docker images and the empty runtime volume may remain for reuse.

## Prerequisites

- **Docker** (with Docker Compose v2)
- **Make**
- **Linux** or **macOS** (Windows support on roadmap)

---

## Quick Start (Interactive)

For the best experience, use the interactive menu:

```bash
make menu
```

This TUI (Text User Interface) allows you to:
- 🚀 **Start Stack** (Server + DB)
- 📊 **Stack Status** (View URL and registered Tentacles)
- 🐙 **Manage Tentacles** (Add, Remove, View Logs)
- 🧹 **Delete Stack** (Nuke everything)

---

## Troubleshooting

```
Error: docker is not running
make: *** [check-docker] Error 1
```
Make sure Docker is running.

## Configuration

### Core Settings
`octopus-local-stack.yaml` contains non-secret stack settings such as endpoints, account names, and resource identifiers.

An Octopus Server licence is required. Export the base64-encoded licence before starting the stack:

```bash
export OCTOPUS_SERVER_BASE64_LICENSE="<base64-encoded-licence>"
make menu
```

Startup stops with an error if `OCTOPUS_SERVER_BASE64_LICENSE` is unset or empty.

The stack generates its SQL password, Octopus administrator password, API key, master key, and instance ID on first startup. The API key is provisioned through Octopus Server's native `ADMIN_API_KEY` container setting. These values are stored in a dedicated Docker volume rather than in this repository. The master key remains internal to the provider.

When upgrading an existing checkout from the earlier fixed-credential configuration, run `make clean` once before `make up`. Existing server data cannot be paired safely with newly generated credentials.

### Provider Contract

This repository is the runtime provider. A local test suite or other consumer supplies the licence, starts the provider, and requests a validated connection object:

```bash
export OCTOPUS_SERVER_BASE64_LICENSE="<base64-encoded-licence>"
make up
connection_json="$(make --no-print-directory -s connection-json)"
```

`connection-json` succeeds only while the server and database are running, Octopus Server is healthy, and the returned API key authenticates successfully. It writes JSON to standard output so callers can hold it in memory:

```json
{
  "schemaVersion": 1,
  "instanceId": "<generated-instance-id>",
  "octopus": {
    "url": "http://localhost:8080",
    "apiKey": "<generated-api-key>",
    "spaceId": "Spaces-1",
    "adminUsername": "admin",
    "adminPassword": "<generated-password>"
  },
  "docker": {
    "serverContainer": "octopus-server-octopus-server-1",
    "databaseContainer": "octopus-server-db-1",
    "databaseName": "OctopusDeploy",
    "databasePassword": "<generated-password>"
  }
}
```

Consumers must validate `schemaVersion` before using the object and should not write it into either repository.

### Tentacles Configuration
You can define a batch of tentacles in `tentacles.yaml`:

```yaml
tentacles:
  - name: "web-worker-1"
    environment: "Production"
    role: "worker"
    os: "linux"
```

Then apply it with:

```bash
make tentacles-up CONFIG=tentacles.yaml
```

---

## Architecture

### Components

1.  **Server Stack** (`manage_octopus_server.sh`)
    *   **Octopus Server**: The main application.
    *   **SQL Server**: Database backend.
    *   **Credential Provider**: Generates runtime credentials and provisions the API key through Octopus Server's supported container configuration.

2.  **Tentacles** (`manage_tentacles.sh`)
    *   run as separate containers (`docker/tentacles/linux`).
    *   dynamically registered/deregistered via Octopus API.
    *   **Deregistration**: Tentacles are automatically deregistered from the server before their container is stopped, preventing "zombie" targets.

### Directory Structure

```
octopus-local-stack/
├── Makefile                          # Containerised entry points
├── tentacles.yaml                    # Sample tentacle config
├── octopus-local-stack.yaml          # Core config
├── scripts/
│   ├── manage_octopus_server.sh      # Server orchestration
│   ├── manage_tentacles.sh           # Tentacle orchestration
│   ├── menu.sh                       # Interactive TUI
│   ├── cleanup.sh                    # Nuke script
│   ├── connection_json.sh            # Validated consumer contract
│   ├── common.sh                     # Shared library
│   ├── docker/                       # Docker helpers
│   └── octopus/                      # API wrappers
├── docker/
│   ├── octopus-server/               # Server compose definitions
│   └── tentacles/
│       └── linux/                    # Linux Tentacle definition
```
