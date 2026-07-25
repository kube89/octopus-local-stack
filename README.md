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

- `make down` stops the server and database, removes Tentacles, and preserves server data in Docker volumes.
- `make clean` removes all stack containers and volumes, including stored server data.

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
- 📊 **Stack Status** (View URL, Creds, registered Tentacles)
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
`octopus-local-stack.yaml` contains the admin credentials, ports, and default API key.

An Octopus Server licence is required. Export the base64-encoded licence before starting the stack:

```bash
export OCTOPUS_SERVER_BASE64_LICENSE="<base64-encoded-licence>"
make menu
```

Startup stops with an error if `OCTOPUS_SERVER_BASE64_LICENSE` is unset or empty.

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
    *   **API Key Seeding**: Pre-hashed key injected for immediate automation.

2.  **Tentacles** (`manage_tentacles.sh`)
    *   run as separate containers (`docker/tentacles/linux`).
    *   dynamically registered/deregistered via Octopus API.
    *   **Deregistration**: Tentacles are automatically deregistered from the server before their container is stopped, preventing "zombie" targets.

### Directory Structure

```
octopus-local-stack/
├── Makefile                          # Legacy/Alias entry points
├── tentacles.yaml                    # Sample tentacle config
├── octopus-local-stack.yaml          # Core config
├── scripts/
│   ├── manage_octopus_server.sh      # Server orchestration
│   ├── manage_tentacles.sh           # Tentacle orchestration
│   ├── menu.sh                       # Interactive TUI
│   ├── cleanup.sh                    # Nuke script
│   ├── common.sh                     # Shared library
│   ├── docker/                       # Docker helpers
│   └── octopus/                      # API wrappers
├── docker/
│   ├── octopus-server/               # Server compose definitions
│   └── tentacles/
│       └── linux/                    # Linux Tentacle definition
```
