.PHONY: help start stop restart logs status clean build watch monitor

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

start: ## Start THORChain node with complete monitoring
	@echo "🚀 Starting THORChain Node..."
	@if [ ! -f .env ]; then cp thorchain-1.env .env; echo "✅ Created .env file from thorchain-1.env"; fi
	@echo "📋 Current configuration:"
	@grep "THORNODE_VERSION\|RPC_PORT\|P2P_PORT" .env | sed 's/^/   /'
	@echo ""
	@echo "🐳 Starting Docker containers in background..."
	docker compose up -d --no-deps builder
	@echo ""
	@echo "🔨 Following builder logs (will switch to thorchain when ready)..."
	@make watch-all

stop: ## Stop THORChain node
	@echo "🛑 Stopping THORChain node..."
	docker compose down

restart: ## Restart THORChain node
	@echo "🔄 Restarting THORChain node..."
	docker compose restart
	@make watch-thorchain

logs: ## Show logs for thorchain service
	docker compose logs -f thorchain

logs-builder: ## Show logs for builder service
	docker compose logs -f builder

logs-all: ## Show logs for all services
	docker compose logs -f

watch-all: ## Watch both builder and thorchain services intelligently
	@echo "👀 Watching all services..."
	@docker compose logs -f builder 2>/dev/null | while read line; do \
		echo "🔨 BUILDER: $$line"; \
		if echo "$$line" | grep -q "thornode binary is ready\|Build complete\|Successfully tagged"; then \
			echo "✅ Builder service completed successfully!"; \
			echo "🚀 Starting thorchain service..."; \
			docker compose up -d thorchain >/dev/null 2>&1; \
			break; \
		fi; \
		if echo "$$line" | grep -q "ERROR\|FATAL\|failed"; then \
			echo "❌ Builder service encountered an error!"; \
			exit 1; \
		fi; \
	done && \
	echo "⚡ Now following thorchain service..." && \
	docker compose logs -f thorchain 2>/dev/null | while read line; do \
		echo "⚡ THORCHAIN: $$line"; \
		if echo "$$line" | grep -q "started\|sync_info\|started HTTP server\|RPC server\|started P2P\|consensus"; then \
			echo "🎉 THORChain node is starting up!"; \
		fi; \
		if echo "$$line" | grep -q "Initialization complete\|snapshot applied\|started successfully"; then \
			echo "✅ THORChain node initialization completed!"; \
			echo ""; \
			echo "🌐 Node should be accessible at:"; \
			echo "   RPC: http://localhost:$$(grep RPC_PORT .env | cut -d'=' -f2)"; \
			echo "   P2P: localhost:$$(grep P2P_PORT .env | cut -d'=' -f2)"; \
			echo ""; \
			echo "📊 Check node status with: make status"; \
			echo "📱 Monitor with: make monitor"; \
			break; \
		fi; \
		if echo "$$line" | grep -q "ERROR.*database\|FATAL\|panic"; then \
			echo "❌ THORChain node encountered a critical error!"; \
			break; \
		fi; \
	done

watch-builder: ## Watch builder service until thornode binary is ready
	@echo "👀 Watching builder service..."
	@docker compose logs -f builder --since 0s | while read line; do \
		echo "🔨 BUILDER: $$line"; \
		if echo "$$line" | grep -q "thornode binary is ready\|Build complete\|Successfully tagged"; then \
			echo "✅ Builder service completed successfully!"; \
			break; \
		fi; \
		if echo "$$line" | grep -q "ERROR\|FATAL\|failed"; then \
			echo "❌ Builder service encountered an error!"; \
			break; \
		fi; \
	done

watch-thorchain: ## Watch thorchain service until node is ready
	@echo "👀 Watching thorchain service..."
	@timeout 1800 docker compose logs -f thorchain 2>/dev/null | while read line; do \
		echo "⚡ THORCHAIN: $$line"; \
		if echo "$$line" | grep -q "started\|sync_info\|started HTTP server\|RPC server\|started P2P\|consensus"; then \
			echo "🎉 THORChain node is starting up!"; \
		fi; \
		if echo "$$line" | grep -q "Initialization complete\|snapshot applied\|started successfully"; then \
			echo "✅ THORChain node initialization completed!"; \
			echo ""; \
			echo "🌐 Node should be accessible at:"; \
			echo "   RPC: http://localhost:$$(grep RPC_PORT .env | cut -d'=' -f2)"; \
			echo "   P2P: localhost:$$(grep P2P_PORT .env | cut -d'=' -f2)"; \
			echo ""; \
			echo "📊 Check node status with: make status"; \
			echo "📱 Monitor with: make monitor"; \
			break; \
		fi; \
		if echo "$$line" | grep -q "ERROR.*database\|FATAL\|panic"; then \
			echo "❌ THORChain node encountered a critical error!"; \
			break; \
		fi; \
	done || echo "⚠️  THORChain monitoring timed out after 30 minutes"

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
	@echo "🌐 === Node Network Status ==="
	@curl -s http://localhost:$$(grep RPC_PORT .env | cut -d'=' -f2)/status | jq '.result.sync_info' 2>/dev/null || echo "❌ Node not accessible or jq not installed"
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
	sudo rm -rf /mnt/data/blockchain 2>/dev/null || true
	sudo mkdir -p /mnt/data/blockchain && sudo chown 10001:10001 /mnt/data/blockchain
	@echo "✅ Cleanup complete!"

build: ## Force rebuild containers
	docker compose build --no-cache

update: ## Update to latest version (set THORNODE_VERSION in .env first)
	docker compose down
	docker compose build --no-cache
	docker compose up -d
