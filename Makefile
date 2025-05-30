.PHONY: help start stop restart logs status clean build watch monitor setup-data-dir

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start: ## Start Cosmos node with complete monitoring
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found!"; \
		echo "Please copy a chain environment file to .env first:"; \
		echo "  cp <chain>.env .env  # e.g., cp cosmoshub-4.env .env"; \
		echo "  cp cosmoshub-4.env .env"; \
		echo "  cp osmosis-1.env .env"; \
		exit 1; \
	fi
	@NETWORK_NAME=$$(grep "^NETWORK=" .env | cut -d'=' -f2 | head -1); \
	NODE_VERSION=$$(grep "^NODE_VERSION=" .env | cut -d'=' -f2 | head -1); \
	DAEMON_NAME=$$(grep "^DAEMON_NAME=" .env | cut -d'=' -f2 | head -1); \
	RPC_PORT=$$(grep "^RPC_PORT=" .env | cut -d'=' -f2 | head -1); \
	if [ -z "$$RPC_PORT" ]; then RPC_PORT=26657; fi; \
	P2P_PORT=$$(grep "^P2P_PORT=" .env | cut -d'=' -f2 | head -1); \
	if [ -z "$$P2P_PORT" ]; then P2P_PORT=26656; fi; \
	DATA_DIR=$$(grep "^DATA_DIR=" .env | cut -d'=' -f2 | head -1); \
	if [ -n "$$DATA_DIR" ]; then \
		RESOLVED_DATA_DIR=$$(echo "$$DATA_DIR" | sed "s/\$${NETWORK}/$$NETWORK_NAME/g"); \
	else \
		RESOLVED_DATA_DIR="Using Docker volume (default)"; \
	fi; \
	echo "🚀 Starting $$NETWORK_NAME Node..."; \
	echo ""; \
	echo "📋 Current configuration:"; \
	echo "   NODE_VERSION=$$NODE_VERSION"; \
	echo "   NETWORK=$$NETWORK_NAME"; \
	echo "   DAEMON_NAME=$$DAEMON_NAME"; \
	echo "   RPC_PORT=$$RPC_PORT"; \
	echo "   P2P_PORT=$$P2P_PORT"; \
	echo "   DATA_DIR=$$RESOLVED_DATA_DIR"; \
	echo ""; \
	echo "🐳 Starting Docker containers in background..."; \
	docker compose up -d --no-deps builder; \
	echo ""; \
	echo "🔨 Following builder logs (will switch to cosmos when ready)..."
	@make watch-all

stop: ## Stop Cosmos node
	@echo "🛑 Stopping Cosmos node..."
	docker compose down

restart: ## Restart Cosmos node
	@echo "🔄 Restarting Cosmos node..."
	docker compose restart
	@make watch-cosmos

logs: ## Show logs for cosmos service
	docker compose logs -f cosmos

logs-builder: ## Show logs for builder service
	docker compose logs -f builder

logs-all: ## Show logs for all services
	docker compose logs -f

watch-all: ## Watch both builder and cosmos services intelligently
	@echo "👀 Watching all services..."
	@docker compose logs -f builder 2>/dev/null | while read line; do \
		echo "🔨 BUILDER: $$line"; \
		if echo "$$line" | grep -q "binary is ready\|Build complete\|Successfully tagged"; then \
			echo "✅ Builder service completed successfully!"; \
			echo "🚀 Starting cosmos service..."; \
			docker compose up -d cosmos >/dev/null 2>&1; \
			break; \
		fi; \
		if echo "$$line" | grep -q "ERROR\|FATAL\|failed"; then \
			echo "❌ Builder service encountered an error!"; \
			exit 1; \
		fi; \
	done && \
	echo "⚡ Now following cosmos service..." && \
	docker compose logs -f cosmos 2>/dev/null | while read line; do \
		echo "⚡ COSMOS: $$line"; \
		if echo "$$line" | grep -q "started\|sync_info\|started HTTP server\|RPC server\|started P2P\|consensus"; then \
			echo "🎉 Cosmos node is starting up!"; \
		fi; \
		if echo "$$line" | grep -q "Initialization complete\|snapshot applied\|started successfully"; then \
			echo "✅ Cosmos node initialization completed!"; \
			echo ""; \
			echo "📊 Check node status with: make status"; \
			echo "📱 Monitor with: make monitor"; \
			break; \
		fi; \
		if echo "$$line" | grep -q "ERROR.*database\|FATAL\|panic"; then \
			echo "❌ Cosmos node encountered a critical error!"; \
			break; \
		fi; \
	done

watch-builder: ## Watch builder service until node binary is ready
	@echo "👀 Watching builder service..."
	@docker compose logs -f builder --since 0s | while read line; do \
		echo "🔨 BUILDER: $$line"; \
		if echo "$$line" | grep -q "binary is ready\|Build complete\|Successfully tagged"; then \
			echo "✅ Builder service completed successfully!"; \
			break; \
		fi; \
		if echo "$$line" | grep -q "ERROR\|FATAL\|failed"; then \
			echo "❌ Builder service encountered an error!"; \
			break; \
		fi; \
	done

watch-cosmos: ## Watch cosmos service until node is ready
	@echo "👀 Watching cosmos service..."
	@timeout 1800 docker compose logs -f cosmos 2>/dev/null | while read line; do \
		echo "⚡ COSMOS: $$line"; \
		if echo "$$line" | grep -q "started\|sync_info\|started HTTP server\|RPC server\|started P2P\|consensus"; then \
			echo "🎉 Cosmos node is starting up!"; \
		fi; \
		if echo "$$line" | grep -q "Initialization complete\|snapshot applied\|started successfully"; then \
			echo "✅ Cosmos node initialization completed!"; \
			echo ""; \
			echo "📊 Check node status with: make status"; \
			echo "📱 Monitor with: make monitor"; \
			break; \
		fi; \
		if echo "$$line" | grep -q "ERROR.*database\|FATAL\|panic"; then \
			echo "❌ Cosmos node encountered a critical error!"; \
			break; \
		fi; \
	done || echo "⚠️  Cosmos monitoring timed out after 30 minutes"

monitor: ## Run the monitoring script
	@if [ -f monitor.sh ]; then \
		chmod +x monitor.sh && ./monitor.sh; \
	else \
		echo "❌ monitor.sh not found"; \
	fi

status: ## Show comprehensive node status
	@echo "🔍 === Docker Compose Status ==="
	docker compose ps
	@echo ""
	@if [ -f .env ]; then \
		NETWORK_NAME=$$(grep "^NETWORK=" .env | cut -d'=' -f2 | head -1); \
		RPC_PORT=$$(grep "^RPC_PORT=" .env | cut -d'=' -f2 | head -1); \
		if [ -z "$$RPC_PORT" ]; then RPC_PORT=26657; fi; \
		P2P_PORT=$$(grep "^P2P_PORT=" .env | cut -d'=' -f2 | head -1); \
		if [ -z "$$P2P_PORT" ]; then P2P_PORT=26656; fi; \
		echo "🌐 === Node Access Information ==="; \
		echo "   Network: $$NETWORK_NAME"; \
		echo "   RPC: http://localhost:$$RPC_PORT"; \
		echo "   P2P: localhost:$$P2P_PORT"; \
		echo ""; \
		echo "🌐 === Node Network Status ==="; \
		curl -s http://localhost:$$RPC_PORT/status | jq '.result.sync_info' 2>/dev/null || echo "❌ Node not accessible or jq not installed"; \
	else \
		echo "❌ .env file not found"; \
	fi
	@echo ""
	@echo "🔗 === Quick Commands ==="
	@echo "   Logs:     make logs"
	@echo "   Monitor:  make monitor"  
	@echo "   Stop:     make stop"

clean: ## Remove all containers, volumes, and data
	@echo "🧹 Cleaning up all Docker resources and data..."
	docker compose down -v --remove-orphans 2>/dev/null || true
	docker kill $$(docker ps -q) 2>/dev/null || true
	docker system prune -af --volumes
	@if [ -f .env ] && grep -q "^DATA_DIR=" .env; then \
		DATA_PATH=$$(grep "^DATA_DIR=" .env | cut -d'=' -f2); \
		NETWORK_NAME=$$(grep "^NETWORK=" .env | cut -d'=' -f2); \
		RESOLVED_DATA_PATH=$$(echo "$$DATA_PATH" | sed "s/\$${NETWORK}/$$NETWORK_NAME/g"); \
		echo "⚠️  Custom data directory detected: $$RESOLVED_DATA_PATH"; \
		echo "   Data will NOT be automatically removed for safety."; \
		echo "   To manually remove: sudo rm -rf $$RESOLVED_DATA_PATH"; \
	fi
	@echo "✅ Cleanup complete!"

build: ## Force rebuild containers
	docker compose build --no-cache

update: ## Update to latest version (set NODE_VERSION in .env first)
	docker compose down
	docker compose build --no-cache
	docker compose up -d

setup-data-dir: ## Setup custom data directory (requires DATA_DIR in .env)
	@if [ ! -f .env ]; then echo "❌ .env file not found. Copy a chain-specific .env file first (e.g., cp cosmoshub-4.env .env)"; exit 1; fi
	@if ! grep -q "^DATA_DIR=" .env; then echo "❌ DATA_DIR not set in .env file. Please configure DATA_DIR=/your/path"; exit 1; fi
	@DATA_PATH=$$(grep "^DATA_DIR=" .env | cut -d'=' -f2); \
	echo "🗂️  Setting up data directory: $$DATA_PATH"; \
	sudo mkdir -p "$$DATA_PATH" && \
	sudo chown 10001:10001 "$$DATA_PATH" && \
	echo "✅ Data directory $$DATA_PATH is ready!" || \
	echo "❌ Failed to setup data directory. Check permissions and path."

## Development targets

dev: ## Start with development configuration (debug logging, faster health checks)
	@echo "🛠️  Starting in development mode..."
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found!"; \
		echo "Please copy a chain environment file to .env first"; \
		exit 1; \
	fi
	docker compose -f cosmos.yml -f docker-compose.dev.yml up -d

dev-tools: ## Start with development tools (includes utilities like curl, jq, htop)
	@echo "🔧 Starting with development tools..."
	docker compose -f cosmos.yml -f docker-compose.dev.yml --profile dev-tools up -d
	@echo ""
	@echo "💡 Access development tools with:"
	@echo "   docker compose exec dev-tools bash"

dev-monitor: ## Start with full monitoring stack (Prometheus + Grafana)
	@echo "📊 Starting with monitoring stack..."
	docker compose -f cosmos.yml -f docker-compose.dev.yml --profile monitoring up -d
	@echo ""
	@echo "📈 Access monitoring at:"
	@echo "   Grafana: http://localhost:3000 (admin/admin)"
	@echo "   Prometheus: http://localhost:9092"

dev-all: ## Start with all development features (tools + monitoring + logging)
	@echo "🚀 Starting full development environment..."
	docker compose -f cosmos.yml -f docker-compose.dev.yml --profile dev-tools --profile monitoring --profile logging up -d
	@echo ""
	@echo "🎯 Development environment ready:"
	@echo "   Node: http://localhost:$$(grep RPC_PORT .env | cut -d'=' -f2 | head -1)"
	@echo "   Grafana: http://localhost:3000 (admin/admin)"
	@echo "   Prometheus: http://localhost:9092"
	@echo "   Loki: http://localhost:3100"
	@echo "   Tools: docker compose exec dev-tools bash"

dev-stop: ## Stop development environment
	@echo "🛑 Stopping development environment..."
	docker compose -f cosmos.yml -f docker-compose.dev.yml --profile dev-tools --profile monitoring --profile logging down

dev-logs: ## Show development logs
	docker compose -f cosmos.yml -f docker-compose.dev.yml logs -f cosmos
