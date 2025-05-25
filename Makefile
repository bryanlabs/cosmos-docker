.PHONY: help start stop restart logs status clean build

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start: ## Start THORChain node
	@if [ ! -f .env ]; then cp default.env .env; echo "Created .env file from default.env"; fi
	docker compose up -d

stop: ## Stop THORChain node
	docker compose down

restart: ## Restart THORChain node
	docker compose restart

logs: ## Show logs
	docker compose logs -f thorchain

status: ## Show node status
	@echo "=== Docker Compose Status ==="
	docker compose ps
	@echo ""
	@echo "=== Node Status ==="
	@curl -s http://localhost:27147/status | jq '.result.sync_info' 2>/dev/null || echo "Node not accessible or jq not installed"

clean: ## Remove all containers and volumes
	docker compose down -v
	docker system prune -f

build: ## Force rebuild containers
	docker compose build --no-cache

update: ## Update to latest version (set THORNODE_VERSION in .env first)
	docker compose down
	docker compose build --no-cache
	docker compose up -d
