#!/usr/bin/env bash
set -euo pipefail

# Cosmos Node Entrypoint Script
# -----------------------------------
# This script initializes, configures, restores, and starts a Cosmos-based blockchain node.
# It supports:
#   - First-run and restart detection
#   - Genesis file download/replace
#   - Config patching via dasel
#   - Multi-format snapshot restore (aria2c, lz4, gzip, zstd)
#   - Flexible node start command construction
#
# Main flow:
#   1. Validate environment
#   2. Prepare binary
#   3. Initialize chain if needed
#   4. Download/replace genesis if needed
#   5. Apply config overrides
#   6. Restore snapshot if needed
#   7. Start node

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

validate_env() {
  if [ -z "${NETWORK:-}" ]; then
    log "ERROR: NETWORK environment variable is required"; exit 1; fi
  if [ -z "${MONIKER:-}" ]; then
    log "ERROR: MONIKER environment variable is required"; exit 1; fi
}

prepare_binary() {
  BIN_DIR="/tmp/bin"
  mkdir -p ${BIN_DIR}
  if ! cp /builds/${DAEMON_NAME}-${NODE_VERSION} ${BIN_DIR}/${DAEMON_NAME}; then
    log "❌ Failed to copy binary from /builds/${DAEMON_NAME}-${NODE_VERSION} to ${BIN_DIR}/${DAEMON_NAME}"
    ls -la /builds/ || log "Could not list /builds directory"
    exit 1
  fi
  chmod +x ${BIN_DIR}/${DAEMON_NAME}
  export PATH="${BIN_DIR}:${PATH}"
}

init_chain_if_needed() {
  if [ ! -f "${BLOCKCHAIN_HOME}/config/config.toml" ]; then
    log "Initializing chain with default files..."
    ${DAEMON_NAME} init $MONIKER --chain-id $NETWORK --home ${BLOCKCHAIN_HOME}
    log "✅ Chain initialization completed - default files created"
  else
    log "Chain already initialized, skipping init..."
  fi
}

download_genesis_if_needed() {
  if [ -n "${GENESIS_URL:-}" ]; then
    GENESIS_FILE="${BLOCKCHAIN_HOME}/config/genesis.json"
    SHOULD_DOWNLOAD=false
    if [ ! -f "$GENESIS_FILE" ]; then
      SHOULD_DOWNLOAD=true
    else
      GENESIS_SIZE=$(stat -c%s "$GENESIS_FILE" 2>/dev/null || echo "0")
      if [ "$GENESIS_SIZE" -lt 50000 ]; then
        SHOULD_DOWNLOAD=true
      fi
    fi
    if [ "$SHOULD_DOWNLOAD" = "true" ]; then
      log "Downloading genesis from: $GENESIS_URL"
      if curl -f "$GENESIS_URL" -o "$GENESIS_FILE"; then
        log "✅ Genesis file downloaded and replaced successfully"
      else
        log "❌ Failed to download genesis file from $GENESIS_URL"; exit 1
      fi
    fi
  fi
}

apply_config_overrides() {
  CONFIG_FILE="${BLOCKCHAIN_HOME}/config/config.toml"
  APP_CONFIG_FILE="${BLOCKCHAIN_HOME}/config/app.toml"

  # Validate config files exist (they should after init)
  if [ ! -f "$CONFIG_FILE" ]; then
    log "ERROR: config.toml not found at $CONFIG_FILE after init"
    exit 1
  fi

  if [ ! -f "$APP_CONFIG_FILE" ]; then
    log "ERROR: app.toml not found at $APP_CONFIG_FILE after init"
    exit 1
  fi

  # P2P Configuration
  # Handle SEEDS - support both setting and clearing
  if [ "${SEEDS+set}" = "set" ]; then
    if [ -n "$SEEDS" ]; then
      log "Setting seeds: $SEEDS"
      dasel put -t string -f "$CONFIG_FILE" -v "$SEEDS" 'p2p.seeds'
    else
      log "Clearing seeds (empty value provided)"
      dasel put -t string -f "$CONFIG_FILE" -v "" 'p2p.seeds'
    fi
  fi
  
  # Handle PERSISTENT_PEERS - support both setting and clearing
  if [ "${PERSISTENT_PEERS+set}" = "set" ]; then
    if [ -n "$PERSISTENT_PEERS" ]; then
      log "Setting persistent peers: $PERSISTENT_PEERS"
      dasel put -t string -f "$CONFIG_FILE" -v "$PERSISTENT_PEERS" 'p2p.persistent_peers'
    else
      log "Clearing persistent peers (empty value provided)"
      dasel put -t string -f "$CONFIG_FILE" -v "" 'p2p.persistent_peers'
    fi
  fi

  # Network Configuration
  P2P_PORT=${P2P_PORT:-26656}
  if [ -n "${EXTERNAL_ADDRESS:-}" ]; then
    if [ "$EXTERNAL_ADDRESS" = "auto" ]; then
      log "Auto-detecting external IP address..."
      DETECTED_IP=$(curl -s --connect-timeout 10 ifconfig.me -4 || echo "")
      if [ -n "$DETECTED_IP" ]; then
        EXTERNAL_ADDRESS="${DETECTED_IP}:${P2P_PORT}"
        log "Detected external IP: $DETECTED_IP, using external address: $EXTERNAL_ADDRESS"
      else
        log "WARNING: Failed to auto-detect external IP. External address will not be configured."
        EXTERNAL_ADDRESS=""
      fi
    fi
    if [ -n "$EXTERNAL_ADDRESS" ]; then
      log "Setting external address: $EXTERNAL_ADDRESS"
      dasel put -t string -f "$CONFIG_FILE" -v "$EXTERNAL_ADDRESS" 'p2p.external_address'
    fi
  fi

  # Port Configuration
  dasel put -t string -f "$CONFIG_FILE" -v "tcp://0.0.0.0:${RPC_PORT:-26657}" 'rpc.laddr'
  dasel put -t string -f "$CONFIG_FILE" -v "tcp://0.0.0.0:$P2P_PORT" 'p2p.laddr'

  # State Sync Configuration
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_ENABLE:-false}" 'statesync.enable'
  
  # Handle STATESYNC_RPC_SERVERS - support both setting and clearing
  if [ "${STATESYNC_RPC_SERVERS+set}" = "set" ]; then
    if [ -n "$STATESYNC_RPC_SERVERS" ]; then
      log "Setting statesync RPC servers: $STATESYNC_RPC_SERVERS"
      dasel put -f "$CONFIG_FILE" -v "$STATESYNC_RPC_SERVERS" 'statesync.rpc_servers'
    else
      log "Clearing statesync RPC servers (empty value provided)"
      dasel put -f "$CONFIG_FILE" -v "" 'statesync.rpc_servers'
    fi
  fi
  
  # Handle STATESYNC_TRUST_HEIGHT - special case with 0 check
  if [ "${STATESYNC_TRUST_HEIGHT+set}" = "set" ]; then
    if [ -n "$STATESYNC_TRUST_HEIGHT" ] && [ "$STATESYNC_TRUST_HEIGHT" != "0" ]; then
      log "Setting state sync trust height: $STATESYNC_TRUST_HEIGHT"
      dasel put -f "$CONFIG_FILE" -v "$STATESYNC_TRUST_HEIGHT" 'statesync.trust_height'
    else
      log "Clearing state sync trust height (empty or zero value provided)"
      dasel put -f "$CONFIG_FILE" -v "0" 'statesync.trust_height'
    fi
  fi
  if [ "${STATESYNC_TRUST_HASH+set}" = "set" ]; then
    if [ -n "$STATESYNC_TRUST_HASH" ]; then
      log "Setting state sync trust hash: $STATESYNC_TRUST_HASH"
      dasel put -f "$CONFIG_FILE" -v "$STATESYNC_TRUST_HASH" 'statesync.trust_hash'
    else
      log "Clearing state sync trust hash (empty value provided)"
      dasel put -f "$CONFIG_FILE" -v "" 'statesync.trust_hash'
    fi
  fi
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_TRUST_PERIOD:-360h0m0s}" 'statesync.trust_period'
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_DISCOVERY_TIME:-15s}" 'statesync.discovery_time'
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_CHUNK_REQUEST_TIMEOUT:-10s}" 'statesync.chunk_request_timeout'
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_CHUNK_FETCHERS:-4}" 'statesync.chunk_fetchers'

  # Advanced P2P Settings
  dasel put -f "$CONFIG_FILE" -v "${MAX_INBOUND_PEERS:-40}" 'p2p.max_num_inbound_peers'
  dasel put -f "$CONFIG_FILE" -v "${MAX_OUTBOUND_PEERS:-10}" 'p2p.max_num_outbound_peers'
  dasel put -f "$CONFIG_FILE" -v "${P2P_PEX:-true}" 'p2p.pex'
  dasel put -f "$CONFIG_FILE" -v "${P2P_ADDR_BOOK_STRICT:-false}" 'p2p.addr_book_strict'
  dasel put -f "$CONFIG_FILE" -v "${P2P_FLUSH_THROTTLE_TIMEOUT:-100ms}" 'p2p.flush_throttle_timeout'
  dasel put -f "$CONFIG_FILE" -v "${P2P_DIAL_TIMEOUT:-3s}" 'p2p.dial_timeout'
  dasel put -f "$CONFIG_FILE" -v "${P2P_HANDSHAKE_TIMEOUT:-20s}" 'p2p.handshake_timeout'
  dasel put -f "$CONFIG_FILE" -v "${P2P_ALLOW_DUPLICATE_IP:-true}" 'p2p.allow_duplicate_ip'
  # Handle PRIVATE_PEER_IDS - support both setting and clearing
  if [ "${PRIVATE_PEER_IDS+set}" = "set" ]; then
    if [ -n "$PRIVATE_PEER_IDS" ]; then
      log "Setting private peer IDs: $PRIVATE_PEER_IDS"
      dasel put -f "$CONFIG_FILE" -v "$PRIVATE_PEER_IDS" 'p2p.private_peer_ids'
    else
      log "Clearing private peer IDs (empty value provided)"
      dasel put -f "$CONFIG_FILE" -v "" 'p2p.private_peer_ids'
    fi
  fi

  # RPC Configuration
  dasel put -f "$CONFIG_FILE" -v "${RPC_CORS_ALLOWED_ORIGINS:-[\"*\"]}" 'rpc.cors_allowed_origins'
  dasel put -f "$CONFIG_FILE" -v "${RPC_MAX_OPEN_CONNECTIONS:-2000}" 'rpc.max_open_connections'
  dasel put -f "$CONFIG_FILE" -v "${RPC_GRPC_MAX_OPEN_CONNECTIONS:-2000}" 'rpc.grpc_max_open_connections'

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

  # FastSync Configuration
  dasel put -f "$CONFIG_FILE" -v "${FASTSYNC_VERSION:-v0}" 'fastsync.version'

  # TX Index Configuration
  dasel put -f "$CONFIG_FILE" -v "${TX_INDEX_INDEXER:-kv}" 'tx_index.indexer'

  # Instrumentation/Monitoring Configuration
  dasel put -f "$CONFIG_FILE" -v "${PROMETHEUS_ENABLED:-true}" 'instrumentation.prometheus'
  dasel put -f "$CONFIG_FILE" -v "${PROMETHEUS_LISTEN_ADDR:-:26660}" 'instrumentation.prometheus_listen_addr'
  dasel put -f "$CONFIG_FILE" -v "${PROMETHEUS_NAMESPACE:-tendermint}" 'instrumentation.namespace'

  # App Configuration
  dasel put -f "$APP_CONFIG_FILE" -v "true" 'api.enable'
  dasel put -f "$APP_CONFIG_FILE" -v "tcp://0.0.0.0:${REST_PORT:-1317}" 'api.address'
  dasel put -f "$APP_CONFIG_FILE" -v "true" 'grpc.enable'
  dasel put -f "$APP_CONFIG_FILE" -v "0.0.0.0:${GRPC_PORT:-9090}" 'grpc.address'

  # Logging Configuration
  dasel put -f "$CONFIG_FILE" -v "${LOG_LEVEL:-info}" 'log_level'
  dasel put -f "$CONFIG_FILE" -v "${NODE_LOG_FORMAT:-plain}" 'log_format'

  # Minimum gas price configuration
  if [ "${MIN_GAS_PRICE+set}" = "set" ]; then
    if [ -n "$MIN_GAS_PRICE" ]; then
      log "Setting minimum gas price in app.toml: $MIN_GAS_PRICE"
      dasel put -f "$APP_CONFIG_FILE" -v "$MIN_GAS_PRICE" 'minimum-gas-prices' || true
    else
      log "Clearing minimum gas price (empty value provided)"
      dasel put -f "$APP_CONFIG_FILE" -v "" 'minimum-gas-prices' || true
    fi
  fi

  # Pruning configuration
  if [ "${PRUNING_STRATEGY+set}" = "set" ]; then
    if [ -n "$PRUNING_STRATEGY" ]; then
      log "Setting pruning strategy in app.toml: $PRUNING_STRATEGY"
      dasel put -f "$APP_CONFIG_FILE" -v "$PRUNING_STRATEGY" 'pruning' || true

      if [ "$PRUNING_STRATEGY" = "custom" ]; then
        if [ "${PRUNING_KEEP_RECENT+set}" = "set" ] && [ -n "$PRUNING_KEEP_RECENT" ]; then
          log "Setting pruning-keep-recent in app.toml: $PRUNING_KEEP_RECENT"
          dasel put -f "$APP_CONFIG_FILE" -v "$PRUNING_KEEP_RECENT" 'pruning-keep-recent' || true
        fi

        if [ "${PRUNING_INTERVAL+set}" = "set" ] && [ -n "$PRUNING_INTERVAL" ]; then
          log "Setting pruning-interval in app.toml: $PRUNING_INTERVAL"
          dasel put -f "$APP_CONFIG_FILE" -v "$PRUNING_INTERVAL" 'pruning-interval' || true
        fi
      fi
    else
      log "Clearing pruning strategy (empty value provided)"
      dasel put -f "$APP_CONFIG_FILE" -v "default" 'pruning' || true
    fi
  fi

  log "✅ Node configuration applied"
}

restore_snapshot_if_needed() {
  # Skip snapshot if state sync is enabled (check this first)
  if [ "${STATESYNC_ENABLE:-false}" = "true" ]; then
    log "State sync is enabled, skipping snapshot download"
    log "Node will use state sync to quickly sync to current state"
    return
  fi
  
  # Check if database files exist (use a method that doesn't fail with -e flag)
  if [ -d "${BLOCKCHAIN_HOME}/data" ] && [ -n "$(find "${BLOCKCHAIN_HOME}/data" -name "*.db" -type f 2>/dev/null | head -1)" ]; then
    log "Database files already exist, skipping snapshot restore"
    return
  fi
  
  if [ -d "${BLOCKCHAIN_HOME}/data" ]; then
    DATA_FILE_COUNT=$(find ${BLOCKCHAIN_HOME}/data -type f -not -name "priv_validator_state.json" | wc -l)
  else
    DATA_FILE_COUNT=0
  fi
  
  if [ "$DATA_FILE_COUNT" -eq 0 ]; then
    log "Data directory is minimal, checking for snapshot configuration..."
    log "DEBUG: SNAPSHOT='${SNAPSHOT:-}', SNAPSHOT_CHAIN='${SNAPSHOT_CHAIN:-}'"
    
    # Priority 1: Direct snapshot URL (manual override)
    if [ -n "${SNAPSHOT:-}" ] && [ "$SNAPSHOT" != "auto" ]; then
      log "Using direct snapshot URL: $SNAPSHOT"
      if ! download_and_extract_snapshot "$SNAPSHOT"; then
        log "❌ Snapshot download/extraction failed. Will continue without snapshot..."
      fi
      return
    fi
    
    # Priority 2: Polkachu API with auto-detection (default method)
    if [ -n "${SNAPSHOT_CHAIN:-}" ]; then
      log "Detecting latest snapshot for chain: $SNAPSHOT_CHAIN via Polkachu API"
      SNAPSHOT_URL=$(curl -H "x-polkachu: danb" -s "https://polkachu.com/api/v2/chain_snapshots/$SNAPSHOT_CHAIN" | jq -r '.snapshot.url // empty')
      if [ -n "$SNAPSHOT_URL" ] && [ "$SNAPSHOT_URL" != "null" ]; then
        log "Auto-detected snapshot URL: $SNAPSHOT_URL"
        if ! download_and_extract_snapshot "$SNAPSHOT_URL"; then
          log "❌ Auto-detected snapshot download/extraction failed. Will continue without snapshot..."
        fi
        return
      else
        log "❌ Could not auto-detect snapshot URL for chain: $SNAPSHOT_CHAIN. Will continue without snapshot..."
        return
      fi
    fi
    
    # Priority 3: Legacy API (only if explicitly configured with both variables)
    if [ -n "${SNAPSHOT_API_URL:-}" ] && [ -n "${SNAPSHOT_BASE_URL:-}" ]; then
      log "Using legacy snapshot API..."
      CHAIN_PREFIX=$(echo "$SNAPSHOT_API_URL" | grep -oE 'prefix=[^&]*' | cut -d'=' -f2 || echo "$DAEMON_NAME")
      FILENAME=$(curl -s "$SNAPSHOT_API_URL" | grep -Eo "${CHAIN_PREFIX}/[0-9]+.tar.gz" | sort -n | tail -n 1 | cut -d "/" -f 2)
      if [ -n "$FILENAME" ]; then
        log "Using latest snapshot: $FILENAME"
        if ! download_and_extract_snapshot "${SNAPSHOT_BASE_URL}${FILENAME}"; then
          log "❌ Snapshot download/extraction failed. Will continue without snapshot..."
        fi
      else
        log "No snapshot found via legacy API, will start syncing from genesis block 1..."
      fi
      return
    fi
    
    # No snapshot configuration found
    log "No snapshot configuration found, will start syncing from genesis block 1..."
  else
    log "Data directory contains files, skipping snapshot restore"
  fi
}

build_start_command() {
  CMD="${DAEMON_NAME} start --home ${BLOCKCHAIN_HOME}"
  
  # Add minimum gas price if set
  if [ "${MIN_GAS_PRICE+set}" = "set" ] && [ -n "$MIN_GAS_PRICE" ]; then
    CMD="$CMD --minimum-gas-prices=$MIN_GAS_PRICE"
  fi
  
  # Add pruning configuration if set
  if [ "${PRUNING_STRATEGY+set}" = "set" ] && [ -n "$PRUNING_STRATEGY" ]; then
    CMD="$CMD --pruning=$PRUNING_STRATEGY"
    if [ "$PRUNING_STRATEGY" = "custom" ]; then
      if [ "${PRUNING_KEEP_RECENT+set}" = "set" ] && [ -n "$PRUNING_KEEP_RECENT" ]; then
        CMD="$CMD --pruning-keep-recent=$PRUNING_KEEP_RECENT"
      fi
      if [ "${PRUNING_INTERVAL+set}" = "set" ] && [ -n "$PRUNING_INTERVAL" ]; then
        CMD="$CMD --pruning-interval=$PRUNING_INTERVAL"
      fi
    fi
  fi
  
  # Add extra flags if set
  if [ "${EXTRA_FLAGS+set}" = "set" ] && [ -n "$EXTRA_FLAGS" ]; then
    CMD="$CMD $EXTRA_FLAGS"
  fi
  
  echo "$CMD"
}

# Function to download, decompress, extract, and clean up snapshot
# Usage: download_and_extract_snapshot <snapshot_url>
download_and_extract_snapshot() {
  local SNAP_URL="$1"
  local FILENAME FILEPATH
  FILENAME=$(basename "$SNAP_URL")
  log "Downloading snapshot: $SNAP_URL"
  aria2c --split=16 --max-concurrent-downloads=16 --max-connection-per-server=16 --continue --min-split-size=100M -d ${BLOCKCHAIN_HOME} -o "$FILENAME" "$SNAP_URL"
  FILEPATH="${BLOCKCHAIN_HOME}/$FILENAME"
  if [[ "$FILENAME" == *.tar.lz4 ]]; then
    log "Decompressing LZ4 archive..."
    lz4 -c -d "$FILEPATH" > "${BLOCKCHAIN_HOME}/snapshot.tar"
    rm "$FILEPATH"
  elif [[ "$FILENAME" == *.tar.gz ]]; then
    log "Decompressing GZ archive..."
    gzip -d -c "$FILEPATH" > "${BLOCKCHAIN_HOME}/snapshot.tar"
    rm "$FILEPATH"
  elif [[ "$FILENAME" == *.tar.zst ]]; then
    log "Decompressing ZST archive..."
    zstd -d -c "$FILEPATH" > "${BLOCKCHAIN_HOME}/snapshot.tar"
    rm "$FILEPATH"
  else
    log "Unsupported snapshot format: $FILENAME"; rm -f "$FILEPATH"; return 1
  fi
  log "Extracting tarball..."
  tar --exclude='data/priv_validator_state.json' -xvf "${BLOCKCHAIN_HOME}/snapshot.tar" -C ${BLOCKCHAIN_HOME}
  rm "${BLOCKCHAIN_HOME}/snapshot.tar"
  log "✅ Snapshot extraction completed successfully!"
}

# --- Main Entrypoint Flow ---
DAEMON_NAME=${DAEMON_NAME:-cosmos}
NODE_VERSION=${NODE_VERSION:-v1.0.0}
DAEMON_HOME=${DAEMON_HOME:-/${DAEMON_NAME}}
BLOCKCHAIN_HOME=${DATA_DIR:-${DAEMON_HOME}}
log "Using blockchain data directory: ${BLOCKCHAIN_HOME}"
validate_env
prepare_binary
init_chain_if_needed
download_genesis_if_needed
apply_config_overrides
restore_snapshot_if_needed

# Validate that genesis file exists and is readable
GENESIS_FILE="${BLOCKCHAIN_HOME}/config/genesis.json"
if [ ! -f "$GENESIS_FILE" ]; then
  log "ERROR: Genesis file not found at $GENESIS_FILE"; ls -la ${BLOCKCHAIN_HOME}/config/ || log "Config directory not accessible"; exit 1
fi
if [ ! -r "$GENESIS_FILE" ]; then
  log "ERROR: Genesis file $GENESIS_FILE is not readable"; exit 1
fi
log "✅ Genesis file validation passed: $GENESIS_FILE"

CMD=$(build_start_command)
log "Executing command: $CMD"
exec $CMD
