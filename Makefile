.PHONY: help up down clean connection-json tentacle-up tentacles-up tentacle-down tentacle-clean tentacle-logs cli-build cli-shell shellcheck create-octopus-environment check-docker check-license

# Default target - show help
.DEFAULT_GOAL := help

# CLI container - --build ensures Dockerfile changes are picked up, layer caching makes it fast
CLI_RUN = docker compose -f docker/cli/docker-compose.yml run --build --rm cli
CLI_RUN_NO_BUILD = docker compose -f docker/cli/docker-compose.yml run --rm -T cli
CONFIG ?= tentacles.yaml

# Check Docker is installed and running
check-docker:
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker is not installed"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "Error: docker is not running"; exit 1; }
	@docker compose version >/dev/null 2>&1 || { echo "Error: docker compose is not available"; exit 1; }

# Fail before building the CLI image when the server licence is unavailable
check-license:
	@if [ -z "$(strip $(OCTOPUS_SERVER_BASE64_LICENSE))" ]; then \
		echo "Error: OCTOPUS_SERVER_BASE64_LICENSE must be set before starting the stack."; \
		exit 1; \
	fi

menu: check-license check-docker
	@docker compose -f docker/cli/docker-compose.yml build -q cli
	@echo "Launching Interactive Menu..."
	@docker compose -f docker/cli/docker-compose.yml run --rm cli ./scripts/menu.sh 2>/dev/null

help:
	@echo "Octopus Local Stack"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Stack Commands:"
	@echo "  up                          Start Octopus Server and provision API key"
	@echo "  down                        Stop the stack (keep volumes)"
	@echo "  clean                       Stop and remove all volumes"
	@echo "  connection-json             Print the validated consumer contract"

	@echo ""
	@echo "Tentacle Commands:"
	@echo "  tentacle-up                 Start a tentacle"
	@echo "                              Usage: make tentacle-up NAME=<name> [ENV=<env>] [ROLE=<role>]"
	@echo "  tentacles-up                Start tentacles from a YAML config"
	@echo "                              Usage: make tentacles-up [CONFIG=tentacles.yaml]"
	@echo "  tentacle-down               Stop a tentacle"
	@echo "  tentacle-clean              Stop tentacle and remove volumes"
	@echo "  tentacle-logs               Show tentacle logs"
	@echo ""
	@echo "Octopus Resources:"
	@echo "  create-octopus-environment  Create an environment in Octopus"
	@echo "                              Usage: make create-octopus-environment NAME=<name> [DESC=<desc>]"
	@echo ""
	@echo "CLI:"
	@echo "  cli-shell                   Open shell in CLI container"
	@echo "  cli-build                   Rebuild CLI container"
	@echo "  shellcheck                  Lint all shell scripts"

cli-build: check-docker
	docker compose -f docker/cli/docker-compose.yml build

cli-shell: check-docker
	$(CLI_RUN)

shellcheck: check-docker
	$(CLI_RUN) -lc 'find scripts -type f -name "*.sh" -exec shellcheck -x -P SCRIPTDIR {} +'

# Stack commands (via CLI container)
up: check-license check-docker
	$(CLI_RUN) ./scripts/manage_octopus_server.sh up

down: check-docker
	$(CLI_RUN) ./scripts/manage_octopus_server.sh down

clean: check-docker
	$(CLI_RUN) ./scripts/cleanup.sh

connection-json: check-docker
	@$(CLI_RUN_NO_BUILD) ./scripts/connection_json.sh </dev/null

# Tentacle commands (via CLI container)
tentacle-up: check-docker
	@if [ -z "$(NAME)" ]; then echo "Usage: make tentacle-up NAME=<name> [ENV=<env>] [ROLE=<role>]"; exit 1; fi
	$(CLI_RUN) ./scripts/manage_tentacles.sh up $(NAME) $(ENV) $(ROLE)

tentacles-up: check-docker
	@if [ ! -f "$(CONFIG)" ]; then echo "Error: config file not found: $(CONFIG)"; exit 1; fi
	$(CLI_RUN) ./scripts/manage_tentacles.sh up --config "$(CONFIG)" --create-env

tentacle-down: check-docker
	$(CLI_RUN) ./scripts/manage_tentacles.sh down $(NAME)

tentacle-clean: check-docker
	$(CLI_RUN) ./scripts/manage_tentacles.sh clean $(NAME)

tentacle-logs: check-docker
	$(CLI_RUN) ./scripts/manage_tentacles.sh logs $(NAME)

# Octopus resource commands
create-octopus-environment: check-docker
	@if [ -z "$(NAME)" ]; then echo "Usage: make create-octopus-environment NAME=<name> [DESC=<description>]"; exit 1; fi
	$(CLI_RUN) ./scripts/octopus/create_environment.sh "$(NAME)" "$(DESC)"
