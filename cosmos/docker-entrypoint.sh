#!/usr/bin/env bash
set -euo pipefail

# Get daemon name and version from environment
DAEMON_NAME=${DAEMON_NAME:-cosmos}
NODE_VERSION=${NODE_VERSION:-v1.0.0}
DAEMON_HOME=${DAEMON_HOME:-/${DAEMON_NAME}}

# Ensure bin directory exists and copy the binary from builds (always do this)
if ! mkdir -p ${DAEMON_HOME}/bin; then
  echo "❌ Failed to create ${DAEMON_HOME}/bin directory. Check permissions."
  exit 1
fi

if ! cp /builds/${DAEMON_NAME}-${NODE_VERSION} ${DAEMON_HOME}/bin/${DAEMON_NAME}; then
  echo "❌ Failed to copy binary from /builds/${DAEMON_NAME}-${NODE_VERSION} to ${DAEMON_HOME}/bin/${DAEMON_NAME}"
  echo "Available files in /builds:"
  ls -la /builds/ || echo "Could not list /builds directory"
  exit 1
fi

chmod +x ${DAEMON_HOME}/bin/${DAEMON_NAME}

if [[ ! -f ${DAEMON_HOME}/.initialized ]]; then
  echo "Initializing ${DAEMON_NAME} node!"

  echo "Running init..."
  ${DAEMON_HOME}/bin/${DAEMON_NAME} init $MONIKER --chain-id $NETWORK --home ${DAEMON_HOME} --overwrite

  echo "Downloading genesis file..."
  if [ -n "${GENESIS_URL:-}" ]; then
    echo "Using configured genesis URL: $GENESIS_URL"
    echo "Downloading to: ${DAEMON_HOME}/config/genesis.json"
    if curl -f "$GENESIS_URL" -o ${DAEMON_HOME}/config/genesis.json; then
      echo "Genesis file downloaded successfully"
      echo "Genesis file size: $(ls -lh ${DAEMON_HOME}/config/genesis.json | awk '{print $5}')"
    else
      echo "❌ Failed to download genesis file from $GENESIS_URL"
      exit 1
    fi
  else
    echo "No genesis URL configured, skipping genesis download..."
  fi

  if [ -n "${SNAPSHOT:-}" ]; then
    echo "Using specified snapshot: $SNAPSHOT"
    if [[ "$SNAPSHOT" == *.tar.lz4 ]]; then
      echo "Downloading and extracting LZ4 snapshot..."
      curl -o - -L "$SNAPSHOT" | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -xv -C ${DAEMON_HOME}
      echo "LZ4 snapshot extraction completed successfully!"
    elif [[ "$SNAPSHOT" == *.tar.gz ]]; then
      echo "Downloading and extracting GZ snapshot..."
      curl -o - -L "$SNAPSHOT" | tar --exclude='data/priv_validator_state.json' -xzvf - -C ${DAEMON_HOME}
      echo "GZ snapshot extraction completed successfully!"
    else
      echo "Unsupported snapshot format: $SNAPSHOT"
      exit 1
    fi
  elif [ -n "${SNAPSHOT_API_URL:-}" ] && [ -n "${SNAPSHOT_BASE_URL:-}" ]; then
    echo "Fetching latest snapshot automatically..."
    
    # Extract chain name from snapshot API URL for dynamic snapshot detection
    CHAIN_PREFIX=$(echo "$SNAPSHOT_API_URL" | grep -oE 'prefix=[^&]*' | cut -d'=' -f2 || echo "$DAEMON_NAME")
    
    FILENAME=$(curl -s "$SNAPSHOT_API_URL" | grep -Eo "${CHAIN_PREFIX}/[0-9]+.tar.gz" | sort -n | tail -n 1 | cut -d "/" -f 2)
    if [ -n "$FILENAME" ]; then
      echo "Using latest snapshot: $FILENAME"
      aria2c --split=16 --max-concurrent-downloads=16 --max-connection-per-server=16 --continue --min-split-size=100M -d ${DAEMON_HOME} -o $FILENAME "${SNAPSHOT_BASE_URL}${FILENAME}"
      echo "Download completed. Preparing to extract snapshot..."
      rm -rf ${DAEMON_HOME}/data/*.db ${DAEMON_HOME}/data/snapshot ${DAEMON_HOME}/data/cs.wal
      
      # Show file size and start extraction with progress monitoring
      FILESIZE=$(du -h ${DAEMON_HOME}/$FILENAME | cut -f1)
      echo "Extracting snapshot ($FILESIZE)..."
      pv ${DAEMON_HOME}/$FILENAME | tar --exclude='data/priv_validator_state.json' -xzf - -C ${DAEMON_HOME}
      rm ${DAEMON_HOME}/$FILENAME
      echo "Snapshot extraction completed successfully!"
    else
      echo "No snapshot found, starting from genesis..."
    fi
  else
    echo "No snapshot configuration provided, starting from genesis..."
  fi

  echo "Setting up configuration..."
  
  # Update config.toml
  CONFIG_FILE="${DAEMON_HOME}/config/config.toml"
  
  # P2P Configuration
  if [ -n "${SEEDS:-}" ]; then
    echo "Setting seeds: $SEEDS"
    dasel put -t string -f "$CONFIG_FILE" -v "$SEEDS" 'p2p.seeds'
  fi
  
  if [ -n "${PERSISTENT_PEERS:-}" ]; then
    echo "Setting persistent peers: $PERSISTENT_PEERS"
    dasel put -t string -f "$CONFIG_FILE" -v "$PERSISTENT_PEERS" 'p2p.persistent_peers'
  fi
  
  # Ensure P2P_PORT has a valid default value BEFORE using it
  P2P_PORT=${P2P_PORT:-26656}
  echo "Using P2P_PORT: $P2P_PORT"
  
  # Validate that P2P_PORT is a valid number
  if ! [[ "$P2P_PORT" =~ ^[0-9]+$ ]]; then
    echo "ERROR: P2P_PORT must be a valid port number, got: $P2P_PORT"
    exit 1
  fi
  
  if [ -n "${EXTERNAL_ADDRESS:-}" ]; then
    if [ "$EXTERNAL_ADDRESS" = "auto" ]; then
      echo "Auto-detecting external IP address..."
      DETECTED_IP=$(curl -s --connect-timeout 10 ifconfig.me -4 || echo "")
      if [ -n "$DETECTED_IP" ]; then
        EXTERNAL_ADDRESS="${DETECTED_IP}:${P2P_PORT}"
        echo "Detected external IP: $DETECTED_IP, using external address: $EXTERNAL_ADDRESS"
      else
        echo "WARNING: Failed to auto-detect external IP. External address will not be configured."
        EXTERNAL_ADDRESS=""
      fi
    fi
    
    if [ -n "$EXTERNAL_ADDRESS" ]; then
      echo "Setting external address: $EXTERNAL_ADDRESS"
      if ! dasel put -t string -f "$CONFIG_FILE" -v "$EXTERNAL_ADDRESS" 'p2p.external_address'; then
        echo "ERROR: Failed to set p2p.external_address in config file"
        exit 1
      fi
    fi
  fi
  
  # Port Configuration
  if ! dasel put -t string -f "$CONFIG_FILE" -v "tcp://0.0.0.0:${RPC_PORT:-26657}" 'rpc.laddr'; then
    echo "ERROR: Failed to set rpc.laddr in config file"
    exit 1
  fi

  # Log the full p2p.laddr value being set
  echo "Setting p2p.laddr to: tcp://0.0.0.0:$P2P_PORT"

  # Update p2p.laddr configuration with explicit type to ensure proper formatting
  P2P_LADDR_VALUE="tcp://0.0.0.0:$P2P_PORT"
  if ! dasel put -t string -f "$CONFIG_FILE" -v "$P2P_LADDR_VALUE" 'p2p.laddr'; then
    echo "ERROR: Failed to set p2p.laddr in config file"
    exit 1
  fi
  
  # Verify the configuration was written correctly
  # Try current dasel syntax first, fallback to alternative if needed
  ACTUAL_P2P_LADDR=$(dasel -f "$CONFIG_FILE" 'p2p.laddr' 2>/dev/null || echo "FAILED_TO_READ")
  # Alternative syntax: ACTUAL_P2P_LADDR=$(dasel select -f "$CONFIG_FILE" 'p2p.laddr' 2>/dev/null || echo "FAILED_TO_READ")
  echo "Verified p2p.laddr set to: $ACTUAL_P2P_LADDR"
  
  if [ -n "${EXTERNAL_ADDRESS:-}" ] && [ "$EXTERNAL_ADDRESS" != "" ]; then
    ACTUAL_EXTERNAL_ADDR=$(dasel -f "$CONFIG_FILE" 'p2p.external_address' 2>/dev/null || echo "FAILED_TO_READ")
    # Alternative syntax: ACTUAL_EXTERNAL_ADDR=$(dasel select -f "$CONFIG_FILE" 'p2p.external_address' 2>/dev/null || echo "FAILED_TO_READ")
    echo "Verified p2p.external_address set to: $ACTUAL_EXTERNAL_ADDR"
  fi
  
  # Advanced P2P Settings
  dasel put -f "$CONFIG_FILE" -v "${MAX_INBOUND_PEERS:-40}" 'p2p.max_num_inbound_peers'
  dasel put -f "$CONFIG_FILE" -v "${MAX_OUTBOUND_PEERS:-10}" 'p2p.max_num_outbound_peers'
  dasel put -f "$CONFIG_FILE" -v "${P2P_PEX:-true}" 'p2p.pex'
  dasel put -f "$CONFIG_FILE" -v "${P2P_ADDR_BOOK_STRICT:-false}" 'p2p.addr_book_strict'
  dasel put -f "$CONFIG_FILE" -v "${P2P_FLUSH_THROTTLE_TIMEOUT:-100ms}" 'p2p.flush_throttle_timeout'
  dasel put -f "$CONFIG_FILE" -v "${P2P_DIAL_TIMEOUT:-3s}" 'p2p.dial_timeout'
  dasel put -f "$CONFIG_FILE" -v "${P2P_HANDSHAKE_TIMEOUT:-20s}" 'p2p.handshake_timeout'
  dasel put -f "$CONFIG_FILE" -v "${P2P_ALLOW_DUPLICATE_IP:-true}" 'p2p.allow_duplicate_ip'
  
  if [ -n "${PRIVATE_PEER_IDS:-}" ]; then
    dasel put -f "$CONFIG_FILE" -v "$PRIVATE_PEER_IDS" 'p2p.private_peer_ids'
  fi
  
  # RPC Configuration
  dasel put -f "$CONFIG_FILE" -v "${RPC_CORS_ALLOWED_ORIGINS:-[\"*\"]}" 'rpc.cors_allowed_origins'
  dasel put -f "$CONFIG_FILE" -v "${RPC_MAX_OPEN_CONNECTIONS:-2000}" 'rpc.max_open_connections'
  dasel put -f "$CONFIG_FILE" -v "${RPC_GRPC_MAX_OPEN_CONNECTIONS:-2000}" 'rpc.grpc_max_open_connections'
  
  # State Sync Configuration
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_ENABLE:-false}" 'statesync.enable'
  if [ -n "${STATESYNC_RPC_SERVERS:-}" ]; then
    dasel put -f "$CONFIG_FILE" -v "$STATESYNC_RPC_SERVERS" 'statesync.rpc_servers'
  fi
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_TRUST_PERIOD:-360h0m0s}" 'statesync.trust_period'
  
  # State sync trust height and hash (required for state sync to work)
  if [ -n "${STATESYNC_TRUST_HEIGHT:-}" ] && [ "${STATESYNC_TRUST_HEIGHT}" != "0" ]; then
    dasel put -f "$CONFIG_FILE" -v "${STATESYNC_TRUST_HEIGHT}" 'statesync.trust_height'
    echo "Setting state sync trust height: ${STATESYNC_TRUST_HEIGHT}"
  fi
  
  if [ -n "${STATESYNC_TRUST_HASH:-}" ]; then
    dasel put -f "$CONFIG_FILE" -v "$STATESYNC_TRUST_HASH" 'statesync.trust_hash'
    echo "Setting state sync trust hash: ${STATESYNC_TRUST_HASH}"
  fi
  
  # Additional state sync configuration
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_DISCOVERY_TIME:-15s}" 'statesync.discovery_time'
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_CHUNK_REQUEST_TIMEOUT:-10s}" 'statesync.chunk_request_timeout'
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_CHUNK_FETCHERS:-4}" 'statesync.chunk_fetchers'
  
  # Consensus Configuration
  dasel put -f "$CONFIG_FILE" -v "${CONSENSUS_TIMEOUT_COMMIT:-5s}" 'consensus.timeout_commit'
  dasel put -f "$CONFIG_FILE" -v "${CONSENSUS_CREATE_EMPTY_BLOCKS:-true}" 'consensus.create_empty_blocks'
  dasel put -f "$CONFIG_FILE" -v "${CONSENSUS_TIMEOUT_PROPOSE:-3s}" 'consensus.timeout_propose'
  dasel put -f "$CONFIG_FILE" -v "${CONSENSUS_TIMEOUT_PROPOSE_DELTA:-500ms}" 'consensus.timeout_propose_delta'
  dasel put -f "$CONFIG_FILE" -v "${CONSENSUS_TIMEOUT_PREVOTE:-1s}" 'consensus.timeout_prevote'
  dasel put -f "$CONFIG_FILE" -v "${CONSENSUS_TIMEOUT_PREVOTE_DELTA:-500ms}" 'consensus.timeout_prevote_delta'
  dasel put -f "$CONFIG_FILE" -v "${CONSENSUS_TIMEOUT_PRECOMMIT:-1s}" 'consensus.timeout_precommit'
  dasel put -f "$CONFIG_FILE" -v "${CONSENSUS_TIMEOUT_PRECOMMIT_DELTA:-500ms}" 'consensus.timeout_precommit_delta'
  
  # Mempool Configuration
  dasel put -f "$CONFIG_FILE" -v "${MEMPOOL_SIZE:-5000}" 'mempool.size'
  dasel put -f "$CONFIG_FILE" -v "${MEMPOOL_CACHE_SIZE:-10000}" 'mempool.cache_size'
  dasel put -f "$CONFIG_FILE" -v "${MEMPOOL_RECHECK:-true}" 'mempool.recheck'
  dasel put -f "$CONFIG_FILE" -v "${MEMPOOL_BROADCAST:-true}" 'mempool.broadcast'
  
  # Instrumentation
  dasel put -f "$CONFIG_FILE" -v "${PROMETHEUS_ENABLED:-true}" 'instrumentation.prometheus'
  dasel put -f "$CONFIG_FILE" -v "${PROMETHEUS_LISTEN_ADDR:-:26660}" 'instrumentation.prometheus_listen_addr'
  dasel put -f "$CONFIG_FILE" -v "${PROMETHEUS_NAMESPACE:-tendermint}" 'instrumentation.namespace'
  
  # FastSync Configuration
  dasel put -f "$CONFIG_FILE" -v "${FASTSYNC_VERSION:-v0}" 'fastsync.version'
  
  # TX Index Configuration
  dasel put -f "$CONFIG_FILE" -v "${TX_INDEX_INDEXER:-kv}" 'tx_index.indexer'
  
  # Log Configuration
  dasel put -f "$CONFIG_FILE" -v "${LOG_LEVEL:-info}" 'log_level'
  dasel put -f "$CONFIG_FILE" -v "${NODE_LOG_FORMAT:-plain}" 'log_format'
  
  # Update app.toml
  APP_CONFIG_FILE="${DAEMON_HOME}/config/app.toml"
  
  # API Configuration
  dasel put -f "$APP_CONFIG_FILE" -v "true" 'api.enable'
  dasel put -f "$APP_CONFIG_FILE" -v "false" 'api.swagger'
  dasel put -f "$APP_CONFIG_FILE" -v "tcp://0.0.0.0:${REST_PORT:-1317}" 'api.address'
  
  # gRPC Configuration
  dasel put -f "$APP_CONFIG_FILE" -v "true" 'grpc.enable'
  dasel put -f "$APP_CONFIG_FILE" -v "0.0.0.0:${GRPC_PORT:-9090}" 'grpc.address'
  
  # gRPC Web Configuration  
  dasel put -f "$APP_CONFIG_FILE" -v "true" 'grpc-web.enable'
  dasel put -f "$APP_CONFIG_FILE" -v "0.0.0.0:${GRPC_WEB_PORT:-9091}" 'grpc-web.address'
  
  # Minimum gas price configuration in app.toml
  if [ -n "${MIN_GAS_PRICE:-}" ]; then
    echo "Setting minimum gas price in app.toml: $MIN_GAS_PRICE"
    dasel put -f "$APP_CONFIG_FILE" -v "$MIN_GAS_PRICE" 'minimum-gas-prices' || true
  fi
  
  # Pruning configuration in app.toml
  if [ -n "${PRUNING_STRATEGY:-}" ]; then
    echo "Setting pruning strategy in app.toml: $PRUNING_STRATEGY"
    dasel put -f "$APP_CONFIG_FILE" -v "$PRUNING_STRATEGY" 'pruning' || true
    
    if [ "$PRUNING_STRATEGY" = "custom" ]; then
      if [ -n "${PRUNING_KEEP_RECENT:-}" ]; then
        echo "Setting pruning-keep-recent in app.toml: $PRUNING_KEEP_RECENT"
        dasel put -f "$APP_CONFIG_FILE" -v "$PRUNING_KEEP_RECENT" 'pruning-keep-recent' || true
      fi
      
      if [ -n "${PRUNING_INTERVAL:-}" ]; then
        echo "Setting pruning-interval in app.toml: $PRUNING_INTERVAL"
        dasel put -f "$APP_CONFIG_FILE" -v "$PRUNING_INTERVAL" 'pruning-interval' || true
      fi
    fi
  fi
  
  touch ${DAEMON_HOME}/.initialized
  echo "Initialization complete!"
fi

# Validate required environment variables
if [ -z "${NETWORK:-}" ]; then
  echo "ERROR: NETWORK environment variable is required"
  exit 1
fi

if [ -z "${MONIKER:-}" ]; then
  echo "ERROR: MONIKER environment variable is required"
  exit 1
fi

# Validate that genesis file exists and is readable
GENESIS_FILE="${DAEMON_HOME}/config/genesis.json"
if [ ! -f "$GENESIS_FILE" ]; then
  echo "ERROR: Genesis file not found at $GENESIS_FILE"
  echo "Available files in config directory:"
  ls -la ${DAEMON_HOME}/config/ || echo "Config directory not accessible"
  exit 1
fi

if [ ! -r "$GENESIS_FILE" ]; then
  echo "ERROR: Genesis file $GENESIS_FILE is not readable"
  exit 1
fi

echo "✅ Genesis file validation passed: $GENESIS_FILE"

# Start the node
echo "Starting ${DAEMON_NAME} node..."
echo "Network: $NETWORK"
echo "Moniker: $MONIKER"
echo "Home: ${DAEMON_HOME}"
echo "Version: $NODE_VERSION"

# Build the command with configured flags
CMD="${DAEMON_HOME}/bin/${DAEMON_NAME} start --home ${DAEMON_HOME}"

# Add minimum gas price if configured
if [ -n "${MIN_GAS_PRICE:-}" ]; then
  echo "Setting minimum gas price: $MIN_GAS_PRICE"
  CMD="$CMD --minimum-gas-prices=$MIN_GAS_PRICE"
fi

# Add pruning configuration if specified
if [ -n "${PRUNING_STRATEGY:-}" ]; then
  echo "Setting pruning strategy: $PRUNING_STRATEGY"
  CMD="$CMD --pruning=$PRUNING_STRATEGY"
  
  # Add additional pruning parameters for custom strategy
  if [ "$PRUNING_STRATEGY" = "custom" ]; then
    if [ -n "${PRUNING_KEEP_RECENT:-}" ]; then
      echo "Setting pruning keep recent: $PRUNING_KEEP_RECENT"
      CMD="$CMD --pruning-keep-recent=$PRUNING_KEEP_RECENT"
    fi
    
    if [ -n "${PRUNING_INTERVAL:-}" ]; then
      echo "Setting pruning interval: $PRUNING_INTERVAL"
      CMD="$CMD --pruning-interval=$PRUNING_INTERVAL"
    fi
  fi
fi

# Add any extra flags if provided
if [ -n "${EXTRA_FLAGS:-}" ]; then
  echo "Adding extra flags: $EXTRA_FLAGS"
  CMD="$CMD $EXTRA_FLAGS"
fi

echo "Executing command: $CMD"

# Execute the command
exec $CMD

