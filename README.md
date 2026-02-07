# Octopus Local Stack

A fully containerized local Octopus Deploy development environment. **Platform agnostic** - only requires Docker.

> [!NOTE] 
> This tool is strictly for **local development and testing**. It acts as a lightweight ephemeral stack and is not intended for production usage or long-lived infrastructure.

## Design Philosophy: Ephemeral Environments

This project operates under the assumption that local Octopus stacks are ephemeral by design.

*   The **Octopus Server** represents the baseline environment.
*   **Tentacles** are treated as disposable tooling for testing and experimentation.
*   When the server stack is torn down, Tentacles are intentionally removed to maintain a clean state.

This behavior is intentional and sets the expectation that persistent Tentacles are explicitely out of scope.

## Prerequisites

- **Docker** (with Docker Compose v2)
- **Linux** or **macOS** (Windows support on roadmap)

---

## Quick Start (Interactive)

For the best experience, use the interactive menu:

```bash
./scripts/menu.sh
```

This TUI (Text User Interface) allows you to:
- 🚀 **Start Stack** (Server + DB)
- 📊 **Stack Status** (View URL, Creds, registered Tentacles)
- 🐙 **Manage Tentacles** (Add, Remove, View Logs)
- 🧹 **Delete Stack** (Nuke everything)

---

## Quick Start (CLI / Automation)

All capabilities are available via scripts for CI/CD or automation.

### 1. Manage Server

```bash
# Start Server
./scripts/manage_octopus_server.sh up

# Check Status
./scripts/manage_octopus_server.sh status

# Stop Server (and deregister all tentacles)
./scripts/manage_octopus_server.sh down
```

### 2. Manage Tentacles

```bash
# Register a single tentacle
./scripts/manage_tentacles.sh up my-tentacle Test web-server

# Register multiple from config file
./scripts/manage_tentacles.sh up --config tentacles.yaml --create-env

# Stop a tentacle
./scripts/manage_tentacles.sh down my-tentacle

# View logs
./scripts/manage_tentacles.sh logs my-tentacle
```

### 3. Cleanup

```bash
# Remove EVERYTHING (containers, volumes, images)
./scripts/cleanup.sh
```

---

## Configuration

### Core Settings
`octopus-local-stack.yaml` contains the admin credentials, ports, and default API key.

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
`./scripts/manage_tentacles.sh up --config tentacles.yaml --create-env`

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