.PHONY: help up down clean tentacle-up tentacle-down tentacle-clean tentacle-logs cli-build cli-shell create-octopus-environment check-docker

# Default target - show help
.DEFAULT_GOAL := help

# CLI container - --build ensures Dockerfile changes are picked up, layer caching makes it fast
CLI_RUN = docker compose -f docker/cli/docker-compose.yml run --build --rm cli

# Check Docker is installed and running
check-docker:
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker is not installed"; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "Error: docker is not running"; exit 1; }
	@docker compose version >/dev/null 2>&1 || { echo "Error: docker compose is not available"; exit 1; }
	
menu: check-docker
	@docker compose -f docker/cli/docker-compose.yml build -q cli
	@echo "Launching Interactive Menu..."
	@docker compose -f docker/cli/docker-compose.yml run --rm cli ./scripts/menu.sh 2>/dev/null

help:
	@echo "Octopus Local Stack"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Stack Commands:"
	@echo "  up                          Start Octopus Server and create API key"
	@echo "  down                        Stop the stack (keep volumes)"
	@echo "  clean                       Stop and remove all volumes"

	@echo ""
	@echo "Tentacle Commands:"
	@echo "  tentacle-up                 Start a tentacle"
	@echo "                              Usage: make tentacle-up NAME=<name> [ENV=<env>] [ROLE=<role>]"
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

cli-build: check-docker
	docker compose -f docker/cli/docker-compose.yml build

cli-shell: check-docker
	$(CLI_RUN)

# Stack commands (via CLI container)
up: check-docker
	$(CLI_RUN) ./scripts/manage_octopus_server.sh up

down: check-docker
	$(CLI_RUN) ./scripts/manage_octopus_server.sh down

clean: check-docker
	$(CLI_RUN) ./scripts/cleanup.sh

# Tentacle commands (via CLI container)
tentacle-up: check-docker
	@if [ -z "$(NAME)" ]; then echo "Usage: make tentacle-up NAME=<name> [ENV=<env>] [ROLE=<role>]"; exit 1; fi
	$(CLI_RUN) ./scripts/manage_tentacles.sh up $(NAME) $(ENV) $(ROLE)

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
