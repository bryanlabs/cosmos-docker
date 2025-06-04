.PHONY: help start stop restart logs status clean clean-all clean-images clean-builds build watch monitor setup-data-dir

help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# === CHAIN MANAGEMENT ===

chains: ## List all available chains
	@./scripts/chain-manager.sh list

use: ## Set active chain (Usage: make use CHAIN=kaiyo-1)
	@if [ -z "$(CHAIN)" ]; then \
		echo "❌ Please specify a chain: make use CHAIN=<chain-id>"; \
		echo "Available chains:"; \
		./scripts/chain-manager.sh list; \
		exit 1; \
	fi
	@./scripts/chain-manager.sh use $(CHAIN)

pull: ## Pull chain config from registry (Usage: make pull CHAIN=osmosis)
	@if [ -z "$(CHAIN)" ]; then \
		echo "❌ Please specify a chain: make pull CHAIN=<chain-name>"; \
		exit 1; \
	fi
	@./scripts/chain-manager.sh pull $(CHAIN)

create: ## Create custom chain config (Usage: make create CHAIN=my-devnet)
	@if [ -z "$(CHAIN)" ]; then \
		echo "❌ Please specify a chain: make create CHAIN=<chain-id>"; \
		exit 1; \
	fi
	@./scripts/chain-manager.sh create $(CHAIN)

validate: ## Validate chain config (Usage: make validate CHAIN=kaiyo-1)
	@if [ -z "$(CHAIN)" ]; then \
		echo "❌ Please specify a chain: make validate CHAIN=<chain-id>"; \
		exit 1; \
	fi
	@./scripts/chain-manager.sh validate $(CHAIN)

# === NODE OPERATIONS ===

start: ## Start Cosmos node with complete monitoring
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found!"; \
		echo "Please copy a chain environment file to .env first:"; \
		echo "  cp <chain>.env .env  # e.g., cp cosmoshub-4.env .env"; \
		echo "  cp cosmoshub-4.env .env"; \
		echo "  cp osmosis-1.env .env"; \
		exit 1; \
	fi
	@DATA_DIR_FROM_ENV=$$(grep "^DATA_DIR=" .env 2>/dev/null | cut -d'=' -f2 || true); \
	DATA_DIR_FROM_DEFAULTS=$$(grep "^DATA_DIR=" defaults.env 2>/dev/null | cut -d'=' -f2 || true); \
	EFFECTIVE_DATA_DIR=$${DATA_DIR_FROM_ENV:-$$DATA_DIR_FROM_DEFAULTS}; \
	if [ -n "$$EFFECTIVE_DATA_DIR" ]; then \
		echo "🗂️  Custom DATA_DIR detected: $$EFFECTIVE_DATA_DIR"; \
		echo "🗂️  Setting up directory..."; \
		$(MAKE) setup-data-dir; \
	fi
	@NETWORK_NAME=$$(grep "^NETWORK=" .env | cut -d'=' -f2 | head -1); \
	NODE_VERSION=$$(grep "^NODE_VERSION=" .env | cut -d'=' -f2 | head -1); \
	DAEMON_NAME=$$(grep "^DAEMON_NAME=" .env | cut -d'=' -f2 | head -1); \
	RPC_PORT=$$(grep "^RPC_PORT=" .env | cut -d'=' -f2 | head -1); \
	if [ -z "$$RPC_PORT" ]; then RPC_PORT=26657; fi; \
	P2P_PORT=$$(grep "^P2P_PORT=" .env | cut -d'=' -f2 | head -1); \
	if [ -z "$$P2P_PORT" ]; then P2P_PORT=26656; fi; \
	REST_PORT=$$(grep "^REST_PORT=" .env | cut -d'=' -f2 | head -1); \
	if [ -z "$$REST_PORT" ]; then REST_PORT=1317; fi; \
	GRPC_PORT=$$(grep "^GRPC_PORT=" .env | cut -d'=' -f2 | head -1); \
	if [ -z "$$GRPC_PORT" ]; then GRPC_PORT=9090; fi; \
	GRPC_WEB_PORT=$$(grep "^GRPC_WEB_PORT=" .env | cut -d'=' -f2 | head -1); \
	if [ -z "$$GRPC_WEB_PORT" ]; then GRPC_WEB_PORT=9091; fi; \
	EXTERNAL_ADDRESS=$$(grep "^EXTERNAL_ADDRESS=" .env | cut -d'=' -f2 | head -1); \
	if [ -z "$$EXTERNAL_ADDRESS" ] || [ "$$EXTERNAL_ADDRESS" = "auto" ]; then \
		EXTERNAL_IP=$$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "localhost"); \
	else \
		EXTERNAL_IP="$$EXTERNAL_ADDRESS"; \
	fi; \
	DATA_DIR_FROM_ENV=$$(grep "^DATA_DIR=" .env 2>/dev/null | cut -d'=' -f2 || true); \
	DATA_DIR_FROM_DEFAULTS=$$(grep "^DATA_DIR=" defaults.env 2>/dev/null | cut -d'=' -f2 || true); \
	DATA_DIR=$${DATA_DIR_FROM_ENV:-$$DATA_DIR_FROM_DEFAULTS}; \
	if [ -n "$$DATA_DIR" ]; then \
		RESOLVED_DATA_DIR=$$(echo "$$DATA_DIR" | sed "s/\$${NETWORK}/$$NETWORK_NAME/g"); \
	else \
		RESOLVED_DATA_DIR="Using Docker volume (default)"; \
	fi; \
	echo "🚀 Starting $$NETWORK_NAME Node..."; \
	echo ""; \
	echo "📋 Configuration Summary:"; \
	echo "   \033[1;33mNetwork:\033[0m $$NETWORK_NAME ($$NODE_VERSION)"; \
	echo "   \033[1;33mDaemon:\033[0m $$DAEMON_NAME"; \
	echo "   \033[1;33mData Dir:\033[0m $$RESOLVED_DATA_DIR"; \
	echo ""; \
	echo "🌐 Network Endpoints (will be available after startup):"; \
	echo "   \033[1;33mRPC:\033[0m     http://$$EXTERNAL_IP:$$RPC_PORT"; \
	echo "   \033[1;33mAPI:\033[0m     http://$$EXTERNAL_IP:$$REST_PORT"; \
	echo "   \033[1;33mP2P:\033[0m     $$EXTERNAL_IP:$$P2P_PORT"; \
	echo "   \033[1;33mgRPC:\033[0m    $$EXTERNAL_IP:$$GRPC_PORT"; \
	echo "   \033[1;33mgRPC-Web:\033[0m http://$$EXTERNAL_IP:$$GRPC_WEB_PORT"; \
	echo ""; \
	echo "💡 Use '\033[1;32mmake status\033[0m' after startup for detailed node information including P2P ID"; \
	echo ""; \
	echo "🐳 Starting Docker containers in background..."; \
	HOST_UID=$$(id -u) HOST_GID=$$(id -g) docker compose up -d --no-deps builder; \
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
		if echo "$$line" | grep -q "binary is ready\|Build complete\|Successfully tagged\|Skipping build"; then \
			echo "✅ Builder service completed successfully!"; \
			echo "🚀 Starting cosmos service..."; \
			HOST_UID=$$(id -u) HOST_GID=$$(id -g) docker compose up -d cosmos >/dev/null 2>&1; \
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
		if echo "$$line" | grep -q "binary is ready\|Build complete\|Successfully tagged\|Skipping build"; then \
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
	@echo "\033[1;36m🔍 === Docker Compose Status ===\033[0m"
	@echo "\033[1;33mContainer Status:\033[0m"
	@for container in $$(docker compose ps -q 2>/dev/null); do \
		if [ -n "$$container" ]; then \
			NAME=$$(docker inspect --format='{{.Name}}' $$container | sed 's|^/||'); \
			IMAGE=$$(docker inspect --format='{{.Config.Image}}' $$container); \
			STATUS=$$(docker inspect --format='{{.State.Status}}' $$container); \
			HEALTH=$$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' $$container 2>/dev/null); \
			RPC_PORT_MAP=$$(docker inspect --format='{{range $$key, $$value := .NetworkSettings.Ports}}{{if eq $$key "26657/tcp"}}{{range $$value}}{{.HostPort}}{{break}}{{end}}{{end}}{{end}}' $$container); \
			REST_PORT_MAP=$$(docker inspect --format='{{range $$key, $$value := .NetworkSettings.Ports}}{{if eq $$key "1317/tcp"}}{{range $$value}}{{.HostPort}}{{break}}{{end}}{{end}}{{end}}' $$container); \
			P2P_PORT_MAP=$$(docker inspect --format='{{range $$key, $$value := .NetworkSettings.Ports}}{{if eq $$key "26656/tcp"}}{{range $$value}}{{.HostPort}}{{break}}{{end}}{{end}}{{end}}' $$container); \
			GRPC_PORT_MAP=$$(docker inspect --format='{{range $$key, $$value := .NetworkSettings.Ports}}{{if eq $$key "9090/tcp"}}{{range $$value}}{{.HostPort}}{{break}}{{end}}{{end}}{{end}}' $$container); \
			GRPC_WEB_PORT_MAP=$$(docker inspect --format='{{range $$key, $$value := .NetworkSettings.Ports}}{{if eq $$key "9091/tcp"}}{{range $$value}}{{.HostPort}}{{break}}{{end}}{{end}}{{end}}' $$container); \
			PROMETHEUS_PORT_MAP=$$(docker inspect --format='{{range $$key, $$value := .NetworkSettings.Ports}}{{if eq $$key "26660/tcp"}}{{range $$value}}{{.HostPort}}{{break}}{{end}}{{end}}{{end}}' $$container); \
			if [ "$$STATUS" = "running" ]; then \
				echo "   \033[1;32m✅ $$NAME\033[0m (\033[1;34m$$IMAGE\033[0m) - \033[1;32mrunning\033[0m"; \
			else \
				echo "   \033[1;31m❌ $$NAME\033[0m (\033[1;34m$$IMAGE\033[0m) - \033[1;31m$$STATUS\033[0m"; \
			fi; \
			if [ "$$HEALTH" != "no healthcheck" ] && [ "$$HEALTH" != "" ]; then \
				if [ "$$HEALTH" = "healthy" ]; then \
					echo "      \033[1;33mHealth:\033[0m \033[1;32m$$HEALTH\033[0m"; \
				elif [ "$$HEALTH" = "starting" ] || [ "$$HEALTH" = "unhealthy" ]; then \
					echo "      \033[1;33mHealth:\033[0m \033[1;33m$$HEALTH\033[0m"; \
				else \
					echo "      \033[1;33mHealth:\033[0m \033[1;31m$$HEALTH\033[0m"; \
				fi; \
			fi; \
			PORTS_LIST=""; \
			if [ -n "$$RPC_PORT_MAP" ]; then \
				if [ -z "$$PORTS_LIST" ]; then PORTS_LIST="\033[1;32mRPC\033[0m:\033[1;95m$$RPC_PORT_MAP\033[0m"; else PORTS_LIST="$$PORTS_LIST, \033[1;32mRPC\033[0m:\033[1;95m$$RPC_PORT_MAP\033[0m"; fi; \
			fi; \
			if [ -n "$$REST_PORT_MAP" ]; then \
				if [ -z "$$PORTS_LIST" ]; then PORTS_LIST="\033[1;32mAPI\033[0m:\033[1;95m$$REST_PORT_MAP\033[0m"; else PORTS_LIST="$$PORTS_LIST, \033[1;32mAPI\033[0m:\033[1;95m$$REST_PORT_MAP\033[0m"; fi; \
			fi; \
			if [ -n "$$P2P_PORT_MAP" ]; then \
				if [ -z "$$PORTS_LIST" ]; then PORTS_LIST="\033[1;32mP2P\033[0m:\033[1;95m$$P2P_PORT_MAP\033[0m"; else PORTS_LIST="$$PORTS_LIST, \033[1;32mP2P\033[0m:\033[1;95m$$P2P_PORT_MAP\033[0m"; fi; \
			fi; \
			if [ -n "$$GRPC_PORT_MAP" ]; then \
				if [ -z "$$PORTS_LIST" ]; then PORTS_LIST="\033[1;32mgRPC\033[0m:\033[1;95m$$GRPC_PORT_MAP\033[0m"; else PORTS_LIST="$$PORTS_LIST, \033[1;32mgRPC\033[0m:\033[1;95m$$GRPC_PORT_MAP\033[0m"; fi; \
			fi; \
			if [ -n "$$GRPC_WEB_PORT_MAP" ]; then \
				if [ -z "$$PORTS_LIST" ]; then PORTS_LIST="\033[1;32mgRPC-Web\033[0m:\033[1;95m$$GRPC_WEB_PORT_MAP\033[0m"; else PORTS_LIST="$$PORTS_LIST, \033[1;32mgRPC-Web\033[0m:\033[1;95m$$GRPC_WEB_PORT_MAP\033[0m"; fi; \
			fi; \
			if [ -n "$$PROMETHEUS_PORT_MAP" ]; then \
				if [ -z "$$PORTS_LIST" ]; then PORTS_LIST="\033[1;32mMetrics\033[0m:\033[1;95m$$PROMETHEUS_PORT_MAP\033[0m"; else PORTS_LIST="$$PORTS_LIST, \033[1;32mMetrics\033[0m:\033[1;95m$$PROMETHEUS_PORT_MAP\033[0m"; fi; \
			fi; \
			if [ -n "$$PORTS_LIST" ]; then \
				echo "      \033[1;33mPorts:\033[0m $$PORTS_LIST"; \
			fi; \
		fi; \
	done
	@echo ""
	@if [ -f .env ]; then \
		NETWORK_NAME=$$(grep "^NETWORK=" .env | cut -d'=' -f2 | head -1); \
		RPC_PORT=$$(grep "^RPC_PORT=" .env | cut -d'=' -f2 | head -1); \
		if [ -z "$$RPC_PORT" ]; then RPC_PORT=26657; fi; \
		P2P_PORT=$$(grep "^P2P_PORT=" .env | cut -d'=' -f2 | head -1); \
		if [ -z "$$P2P_PORT" ]; then P2P_PORT=26656; fi; \
		PUBLIC_API_URL=$$(grep "^PUBLIC_API_URL=" .env | cut -d'=' -f2 | head -1); \
		REST_PORT=$$(grep "^REST_PORT=" .env | cut -d'=' -f2 | head -1); \
		if [ -z "$$REST_PORT" ]; then REST_PORT=1317; fi; \
		GRPC_PORT=$$(grep "^GRPC_PORT=" .env | cut -d'=' -f2 | head -1); \
		if [ -z "$$GRPC_PORT" ]; then GRPC_PORT=9090; fi; \
		GRPC_WEB_PORT=$$(grep "^GRPC_WEB_PORT=" .env | cut -d'=' -f2 | head -1); \
		if [ -z "$$GRPC_WEB_PORT" ]; then GRPC_WEB_PORT=9091; fi; \
		EXTERNAL_ADDRESS=$$(grep "^EXTERNAL_ADDRESS=" .env | cut -d'=' -f2 | head -1); \
		if [ -z "$$EXTERNAL_ADDRESS" ] || [ "$$EXTERNAL_ADDRESS" = "auto" ]; then \
			EXTERNAL_ADDRESS=$$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "unknown"); \
		fi; \
		echo "\033[1;36m🌐 === Node Access Information ===\033[0m"; \
		echo "   \033[1;33mNetwork:\033[0m \033[1;32m$$NETWORK_NAME\033[0m"; \
		echo "   \033[1;33mRPC:\033[0m \033[1;34mhttp://$$EXTERNAL_ADDRESS:$$RPC_PORT\033[0m"; \
		echo "   \033[1;33mAPI:\033[0m \033[1;34mhttp://$$EXTERNAL_ADDRESS:$$REST_PORT\033[0m"; \
		echo "   \033[1;33mgRPC:\033[0m \033[1;34m$$EXTERNAL_ADDRESS:$$GRPC_PORT\033[0m"; \
		echo "   \033[1;33mgRPC-Web:\033[0m \033[1;34mhttp://$$EXTERNAL_ADDRESS:$$GRPC_WEB_PORT\033[0m"; \
		NODE_ID=$$(curl -s http://localhost:$$RPC_PORT/status 2>/dev/null | jq -r '.result.node_info.id' 2>/dev/null); \
		if [ "$$NODE_ID" != "null" ] && [ "$$NODE_ID" != "" ]; then \
			echo "   \033[1;33mP2P ID:\033[0m \033[1;35m$$NODE_ID\033[0m@\033[1;32m$$EXTERNAL_ADDRESS\033[0m:\033[1;34m$$P2P_PORT\033[0m"; \
		else \
			echo "   \033[1;33mP2P ID:\033[0m \033[1;31m❌ Unable to retrieve (node may not be running)\033[0m"; \
		fi; \
		echo ""; \
		echo "\033[1;36m🌐 === Node Network Status ===\033[0m"; \
		NODE_STATUS=$$(curl -s http://localhost:$$RPC_PORT/status 2>/dev/null); \
		if [ -n "$$NODE_STATUS" ]; then \
			LATEST_HEIGHT=$$(echo "$$NODE_STATUS" | jq -r '.result.sync_info.latest_block_height' 2>/dev/null); \
			LATEST_TIME=$$(echo "$$NODE_STATUS" | jq -r '.result.sync_info.latest_block_time' 2>/dev/null); \
			CATCHING_UP=$$(echo "$$NODE_STATUS" | jq -r '.result.sync_info.catching_up' 2>/dev/null); \
			EARLIEST_HEIGHT=$$(echo "$$NODE_STATUS" | jq -r '.result.sync_info.earliest_block_height' 2>/dev/null); \
			NODE_VERSION=$$(echo "$$NODE_STATUS" | jq -r '.result.node_info.version' 2>/dev/null); \
			PEER_COUNT=$$(curl -s http://localhost:$$RPC_PORT/net_info 2>/dev/null | jq -r '.result.n_peers' 2>/dev/null); \
			if [ "$$LATEST_HEIGHT" != "null" ] && [ "$$LATEST_HEIGHT" != "" ]; then \
				echo "   \033[1;33mLatest Block:\033[0m \033[1;32m#$$LATEST_HEIGHT\033[0m"; \
				if [ "$$LATEST_TIME" != "null" ] && [ "$$LATEST_TIME" != "" ]; then \
					FORMATTED_TIME=$$(echo "$$LATEST_TIME" | sed 's/T/ /' | sed 's/\.[0-9]*Z/ UTC/'); \
					echo "   \033[1;33mBlock Time:\033[0m \033[1;34m$$FORMATTED_TIME\033[0m"; \
				fi; \
				if [ "$$EARLIEST_HEIGHT" != "null" ] && [ "$$EARLIEST_HEIGHT" != "" ] && [ "$$EARLIEST_HEIGHT" != "0" ]; then \
					echo "   \033[1;33mEarliest Block:\033[0m \033[1;34m#$$EARLIEST_HEIGHT\033[0m"; \
				fi; \
			fi; \
			if [ "$$NODE_VERSION" != "null" ] && [ "$$NODE_VERSION" != "" ]; then \
				echo "   \033[1;33mNode Version:\033[0m \033[1;34m$$NODE_VERSION\033[0m"; \
			fi; \
			if [ "$$PEER_COUNT" != "null" ] && [ "$$PEER_COUNT" != "" ]; then \
				echo "   \033[1;33mConnected Peers:\033[0m \033[1;32m$$PEER_COUNT\033[0m"; \
			fi; \
			if [ "$$CATCHING_UP" = "true" ]; then \
				if [ -n "$$PUBLIC_API_URL" ]; then \
					CHAIN_HEIGHT=$$(curl -s "$$PUBLIC_API_URL/cosmos/base/tendermint/v1beta1/blocks/latest" 2>/dev/null | jq -r '.block.header.height' 2>/dev/null); \
				else \
					CHAIN_HEIGHT=""; \
				fi; \
				if [ "$$CHAIN_HEIGHT" != "null" ] && [ "$$CHAIN_HEIGHT" != "" ] && [ "$$LATEST_HEIGHT" != "null" ] && [ "$$LATEST_HEIGHT" != "" ]; then \
					BLOCKS_BEHIND=$$((CHAIN_HEIGHT - LATEST_HEIGHT)); \
					if [ $$BLOCKS_BEHIND -gt 0 ]; then \
						echo "   \033[1;33mSync Status:\033[0m \033[1;33m🔄 Syncing (\033[1;31m$$BLOCKS_BEHIND blocks behind\033[1;33m)\033[0m"; \
					else \
						echo "   \033[1;33mSync Status:\033[0m \033[1;33m🔄 Syncing (caught up)\033[0m"; \
					fi; \
				else \
					echo "   \033[1;33mSync Status:\033[0m \033[1;33m🔄 Syncing (catching up)\033[0m"; \
				fi; \
			elif [ "$$CATCHING_UP" = "false" ]; then \
				echo "   \033[1;33mSync Status:\033[0m \033[1;32m✅ Fully synced\033[0m"; \
			else \
				echo "   \033[1;33mSync Status:\033[0m \033[1;31m❓ Unknown\033[0m"; \
			fi; \
		else \
			echo "   \033[1;31m❌ Node not accessible or jq not installed\033[0m"; \
		fi; \
	else \
		echo "\033[1;31m❌ .env file not found\033[0m"; \
	fi
	@echo ""
	@echo "\033[1;36m🔗 === Quick Commands ===\033[0m"
	@echo "   \033[1;33mLogs:\033[0m       \033[1;32mmake logs\033[0m"
	@echo "   \033[1;33mMonitor:\033[0m    \033[1;32mmake monitor\033[0m"  
	@echo "   \033[1;33mStop:\033[0m       \033[1;32mmake stop\033[0m"
	@echo "   \033[1;33mClean:\033[0m      \033[1;32mmake clean\033[0m \033[1;90m(preserves images & builds)\033[0m"
	@echo "   \033[1;33mClean All:\033[0m  \033[1;32mmake clean-all\033[0m \033[1;90m(removes everything)\033[0m"

clean: ## Remove containers and volumes (preserves images and builds)
	@echo "🧹 Cleaning up containers and volumes (preserving images and builds)..."
	docker compose down --remove-orphans 2>/dev/null || true
	@echo "🔍 Removing any remaining containers..."
	@CONTAINERS=$$(docker ps -aq 2>/dev/null); \
	if [ -n "$$CONTAINERS" ]; then \
		docker kill $$CONTAINERS 2>/dev/null || true; \
		docker rm $$CONTAINERS 2>/dev/null || true; \
	fi
	@echo "🗂️  Removing data volumes (preserving build cache)..."
	@VOLUMES=$$(docker volume ls -q 2>/dev/null | grep -v "node-builds\|builds" || true); \
	if [ -n "$$VOLUMES" ]; then \
		echo "$$VOLUMES" | xargs docker volume rm 2>/dev/null || true; \
	fi
	@echo "🧹 Removing unused networks..."
	@docker network prune -f 2>/dev/null || true
	@DATA_DIR_FROM_ENV=$$(grep "^DATA_DIR=" .env 2>/dev/null | cut -d'=' -f2 || true); \
	DATA_DIR_FROM_DEFAULTS=$$(grep "^DATA_DIR=" defaults.env 2>/dev/null | cut -d'=' -f2 || true); \
	DATA_PATH=$${DATA_DIR_FROM_ENV:-$$DATA_DIR_FROM_DEFAULTS}; \
	if [ -n "$$DATA_PATH" ]; then \
		NETWORK_NAME=$$(grep "^NETWORK=" .env | cut -d'=' -f2); \
		RESOLVED_DATA_PATH=$$(echo "$$DATA_PATH" | sed "s/\$${NETWORK}/$$NETWORK_NAME/g"); \
		echo "⚠️  Custom data directory detected: $$RESOLVED_DATA_PATH"; \
		echo "   Data will NOT be automatically removed for safety."; \
		echo "   To manually remove: rm -rf $$RESOLVED_DATA_PATH"; \
	fi
	@echo "✅ Cleanup complete! (Images and build cache preserved for faster rebuilds)"
	@echo "💡 Use 'make clean-all' to remove everything including images and builds"

clean-all: ## Remove everything including images
	@echo "🧹 Complete cleanup - removing containers, volumes, images, and data..."
	docker compose down -v --remove-orphans 2>/dev/null || true
	@echo "🔍 Removing all containers..."
	@CONTAINERS=$$(docker ps -aq 2>/dev/null); \
	if [ -n "$$CONTAINERS" ]; then \
		docker kill $$CONTAINERS 2>/dev/null || true; \
		docker rm $$CONTAINERS 2>/dev/null || true; \
	fi
	@echo "🖼️  Removing all images, volumes, and cache..."
	docker system prune -af --volumes
	@DATA_DIR_FROM_ENV=$$(grep "^DATA_DIR=" .env 2>/dev/null | cut -d'=' -f2 || true); \
	DATA_DIR_FROM_DEFAULTS=$$(grep "^DATA_DIR=" defaults.env 2>/dev/null | cut -d'=' -f2 || true); \
	DATA_PATH=$${DATA_DIR_FROM_ENV:-$$DATA_DIR_FROM_DEFAULTS}; \
	if [ -n "$$DATA_PATH" ]; then \
		NETWORK_NAME=$$(grep "^NETWORK=" .env | cut -d'=' -f2); \
		RESOLVED_DATA_PATH=$$(echo "$$DATA_PATH" | sed "s/\$${NETWORK}/$$NETWORK_NAME/g"); \
		echo "⚠️  Custom data directory detected: $$RESOLVED_DATA_PATH"; \
		echo "   Data will NOT be automatically removed for safety."; \
		echo "   To manually remove: rm -rf $$RESOLVED_DATA_PATH"; \
	fi
	@echo "✅ Complete cleanup finished!"

clean-builds: ## Remove only build cache volumes (forces rebuild)
	@echo "🧹 Removing build cache volumes..."
	@BUILD_VOLUMES=$$(docker volume ls -q 2>/dev/null | grep -E "node-builds|builds" || true); \
	if [ -n "$$BUILD_VOLUMES" ]; then \
		echo "Found build volumes to remove:"; \
		echo "$$BUILD_VOLUMES"; \
		echo "$$BUILD_VOLUMES" | xargs docker volume rm 2>/dev/null || true; \
		echo "✅ Build cache removed - next start will trigger rebuild"; \
	else \
		echo "No build volumes found to remove"; \
	fi

clean-images: ## Remove only built images (cosmos and builder)
	@echo "🖼️  Removing cosmos and builder images..."
	@IMAGES=$$(docker images --format "table {{.Repository}}:{{.Tag}}" | grep -E "(osmosisd|cosmoshub|thorchain|builder):" | awk '{print $$1}' 2>/dev/null); \
	if [ -n "$$IMAGES" ]; then \
		echo "Found images to remove:"; \
		echo "$$IMAGES"; \
		echo "$$IMAGES" | xargs docker rmi -f 2>/dev/null || true; \
		echo "✅ Images removed!"; \
	else \
		echo "No cosmos/builder images found to remove"; \
	fi

build: ## Force rebuild containers
	HOST_UID=$$(id -u) HOST_GID=$$(id -g) docker compose build --no-cache

update: ## Update to latest version (set NODE_VERSION in .env first)
	docker compose down
	HOST_UID=$$(id -u) HOST_GID=$$(id -g) docker compose build --no-cache
	HOST_UID=$$(id -u) HOST_GID=$$(id -g) docker compose up -d

setup-data-dir: ## Setup custom data directory (requires DATA_DIR in .env or defaults.env)
	@if [ ! -f .env ]; then echo "❌ .env file not found. Copy a chain-specific .env file first (e.g., cp cosmoshub-4.env .env)"; exit 1; fi
	@DATA_DIR_FROM_ENV=$$(grep "^DATA_DIR=" .env 2>/dev/null | cut -d'=' -f2 || true); \
	DATA_DIR_FROM_DEFAULTS=$$(grep "^DATA_DIR=" defaults.env 2>/dev/null | cut -d'=' -f2 || true); \
	DATA_PATH=$${DATA_DIR_FROM_ENV:-$$DATA_DIR_FROM_DEFAULTS}; \
	if [ -z "$$DATA_PATH" ]; then echo "❌ DATA_DIR not set in .env or defaults.env file. Please configure DATA_DIR=/your/path"; exit 1; fi; \
	NETWORK_NAME=$$(grep "^NETWORK=" .env | cut -d'=' -f2 | head -1); \
	RESOLVED_DATA_PATH=$$(echo "$$DATA_PATH" | sed "s/\$${NETWORK}/$$NETWORK_NAME/g"); \
	echo "🗂️  Setting up data directory: $$RESOLVED_DATA_PATH"; \
	if [ ! -d "$$RESOLVED_DATA_PATH" ]; then \
		mkdir -p "$$RESOLVED_DATA_PATH" && \
		chown $$(id -u):$$(id -g) "$$RESOLVED_DATA_PATH" && \
		echo "✅ Data directory $$RESOLVED_DATA_PATH created with correct ownership!"; \
	else \
		chown -R $$(id -u):$$(id -g) "$$RESOLVED_DATA_PATH" && \
		echo "✅ Data directory $$RESOLVED_DATA_PATH ownership corrected!"; \
	fi || \
	echo "❌ Failed to setup data directory. Check permissions and path."

## Development targets

dev: ## Start with development configuration (debug logging, faster health checks)
	@echo "🛠️  Starting in development mode..."
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found!"; \
		echo "Please copy a chain environment file to .env first"; \
		exit 1; \
	fi
	HOST_UID=$$(id -u) HOST_GID=$$(id -g) docker compose -f cosmos.yml -f docker-compose.dev.yml up -d

dev-tools: ## Start with development tools (includes utilities like curl, jq, htop)
	@echo "🔧 Starting with development tools..."
	HOST_UID=$$(id -u) HOST_GID=$$(id -g) docker compose -f cosmos.yml -f docker-compose.dev.yml --profile dev-tools up -d
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
