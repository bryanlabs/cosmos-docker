#!/usr/bin/env bash
set -euo pipefail
# Get daemon name and version from environment
DAEMON_NAME=${DAEMON_NAME:-cosmos}
NODE_VERSION=${NODE_VERSION:-v1.0.0}
DAEMON_HOME=${DAEMON_HOME:-/${DAEMON_NAME}}

# Use DATA_DIR as the primary blockchain data location if set, otherwise fall back to DAEMON_HOME
BLOCKCHAIN_HOME=${DATA_DIR:-${DAEMON_HOME}}

echo "Using blockchain data directory: ${BLOCKCHAIN_HOME}"

# Create a local bin directory for the binary (use /tmp/bin which is writable)
BIN_DIR="/tmp/bin"
mkdir -p ${BIN_DIR}

# Ensure bin directory exists and copy the binary from builds (always do this)
if ! cp /builds/${DAEMON_NAME}-${NODE_VERSION} ${BIN_DIR}/${DAEMON_NAME}; then
  echo "❌ Failed to copy binary from /builds/${DAEMON_NAME}-${NODE_VERSION} to ${BIN_DIR}/${DAEMON_NAME}"
  echo "Available files in /builds:"
  ls -la /builds/ || echo "Could not list /builds directory"
  exit 1
fi

chmod +x ${BIN_DIR}/${DAEMON_NAME}

# Add the binary directory to PATH
export PATH="${BIN_DIR}:${PATH}"

# Validate required environment variables early
if [ -z "${NETWORK:-}" ]; then
  echo "ERROR: NETWORK environment variable is required"
  exit 1
fi

if [ -z "${MONIKER:-}" ]; then
  echo "ERROR: MONIKER environment variable is required"
  exit 1
fi

# Step 1: Chain initialization (only if not already initialized)
echo "Step 1: Chain initialization..."
if [ ! -f "${BLOCKCHAIN_HOME}/config/config.toml" ]; then
  echo "Initializing chain with default files..."
  echo "Using blockchain home: ${BLOCKCHAIN_HOME}"
  ${DAEMON_NAME} init $MONIKER --chain-id $NETWORK --home ${BLOCKCHAIN_HOME}
  echo "✅ Chain initialization completed - default files created"
else
  echo "Chain already initialized, skipping init..."
  echo "✅ Using existing chain configuration"
fi

# Step 2: Download and overwrite genesis file if configured
if [ -n "${GENESIS_URL:-}" ]; then
  echo "Step 2: Downloading genesis file..."
  GENESIS_FILE="${BLOCKCHAIN_HOME}/config/genesis.json"
  
  # Check if we should download the genesis file
  SHOULD_DOWNLOAD=false
  
  if [ ! -f "$GENESIS_FILE" ]; then
    echo "Genesis file does not exist, will download..."
    SHOULD_DOWNLOAD=true
  else
    # Check if it's the default genesis (small file) or if we want to force update
    GENESIS_SIZE=$(stat -c%s "$GENESIS_FILE" 2>/dev/null || echo "0")
    if [ "$GENESIS_SIZE" -lt 50000 ]; then  # Less than 50KB is likely default genesis
      echo "Genesis file appears to be default (${GENESIS_SIZE} bytes), will download proper genesis..."
      SHOULD_DOWNLOAD=true
    else
      echo "Genesis file already exists and appears valid (${GENESIS_SIZE} bytes), skipping download..."
    fi
  fi
  
  if [ "$SHOULD_DOWNLOAD" = "true" ]; then
    echo "Downloading from: $GENESIS_URL"
    echo "Target location: $GENESIS_FILE"
    
    if curl -f "$GENESIS_URL" -o "$GENESIS_FILE"; then
      echo "✅ Genesis file downloaded and replaced successfully"
      echo "Genesis file size: $(ls -lh ${BLOCKCHAIN_HOME}/config/genesis.json | awk '{print $5}')"
    else
      echo "❌ Failed to download genesis file from $GENESIS_URL"
      exit 1
    fi
  fi
else
  echo "Step 2: No genesis URL configured, using default genesis from init..."
fi

# Step 3: Apply all configuration updates with dasel
echo "Step 3: Applying node configuration..."
CONFIG_FILE="${BLOCKCHAIN_HOME}/config/config.toml"
APP_CONFIG_FILE="${BLOCKCHAIN_HOME}/config/app.toml"

# Validate config files exist (they should after init)
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.toml not found at $CONFIG_FILE after init"
  exit 1
fi

if [ ! -f "$APP_CONFIG_FILE" ]; then
  echo "ERROR: app.toml not found at $APP_CONFIG_FILE after init"
  exit 1
fi

# P2P Configuration
if [ -n "${SEEDS:-}" ]; then
  echo "Setting seeds: $SEEDS"
  dasel put -t string -f "$CONFIG_FILE" -v "$SEEDS" 'p2p.seeds'
fi
if [ -n "${PERSISTENT_PEERS:-}" ]; then
  echo "Setting persistent peers: $PERSISTENT_PEERS"
  dasel put -t string -f "$CONFIG_FILE" -v "$PERSISTENT_PEERS" 'p2p.persistent_peers'
fi

# Network Configuration
P2P_PORT=${P2P_PORT:-26656}
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
    dasel put -t string -f "$CONFIG_FILE" -v "$EXTERNAL_ADDRESS" 'p2p.external_address'
  fi
fi

# Port Configuration
dasel put -t string -f "$CONFIG_FILE" -v "tcp://0.0.0.0:${RPC_PORT:-26657}" 'rpc.laddr'
dasel put -t string -f "$CONFIG_FILE" -v "tcp://0.0.0.0:$P2P_PORT" 'p2p.laddr'

# State Sync Configuration
dasel put -f "$CONFIG_FILE" -v "${STATESYNC_ENABLE:-false}" 'statesync.enable'
if [ -n "${STATESYNC_RPC_SERVERS:-}" ]; then
  echo "Setting statesync RPC servers: $STATESYNC_RPC_SERVERS"
  dasel put -f "$CONFIG_FILE" -v "$STATESYNC_RPC_SERVERS" 'statesync.rpc_servers'
fi
if [ -n "${STATESYNC_TRUST_HEIGHT:-}" ] && [ "${STATESYNC_TRUST_HEIGHT}" != "0" ]; then
  echo "Setting state sync trust height: ${STATESYNC_TRUST_HEIGHT}"
  dasel put -f "$CONFIG_FILE" -v "${STATESYNC_TRUST_HEIGHT}" 'statesync.trust_height'
fi
if [ -n "${STATESYNC_TRUST_HASH:-}" ]; then
  echo "Setting state sync trust hash: ${STATESYNC_TRUST_HASH}"
  dasel put -f "$CONFIG_FILE" -v "$STATESYNC_TRUST_HASH" 'statesync.trust_hash'
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

# RPC Configuration
dasel put -f "$CONFIG_FILE" -v "${RPC_CORS_ALLOWED_ORIGINS:-[\"*\"]}" 'rpc.cors_allowed_origins'
dasel put -f "$CONFIG_FILE" -v "${RPC_MAX_OPEN_CONNECTIONS:-2000}" 'rpc.max_open_connections'

# App Configuration
dasel put -f "$APP_CONFIG_FILE" -v "true" 'api.enable'
dasel put -f "$APP_CONFIG_FILE" -v "tcp://0.0.0.0:${REST_PORT:-1317}" 'api.address'
dasel put -f "$APP_CONFIG_FILE" -v "true" 'grpc.enable'
dasel put -f "$APP_CONFIG_FILE" -v "0.0.0.0:${GRPC_PORT:-9090}" 'grpc.address'

# Minimum gas price configuration
if [ -n "${MIN_GAS_PRICE:-}" ]; then
  echo "Setting minimum gas price in app.toml: $MIN_GAS_PRICE"
  dasel put -f "$APP_CONFIG_FILE" -v "$MIN_GAS_PRICE" 'minimum-gas-prices' || true
fi

# Pruning configuration
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

echo "✅ Node configuration applied"

# Step 4: Check if snapshot restore is needed
echo "Step 4: Checking snapshot requirements..."
# Check if database files exist (only if data directory exists)
if [ -d "${BLOCKCHAIN_HOME}/data" ]; then
  ls ${BLOCKCHAIN_HOME}/data/*.db 1> /dev/null 2>&1
  DB_EXISTS=$?
else
  echo "Data directory does not exist yet"
  DB_EXISTS=1
fi

if [ $DB_EXISTS -eq 0 ]; then
  echo "Database files already exist, skipping snapshot restore"
else
  echo "No database files found, checking for snapshot configuration..."
  
  # Count actual database/state files (excluding priv_validator_state.json)
  if [ -d "${BLOCKCHAIN_HOME}/data" ]; then
    DATA_FILE_COUNT=$(find ${BLOCKCHAIN_HOME}/data -type f -not -name "priv_validator_state.json" | wc -l)
  else
    DATA_FILE_COUNT=0
  fi
  
  if [ "$DATA_FILE_COUNT" -eq 0 ] && [ -n "${SNAPSHOT:-}" ]; then
    echo "Data directory is minimal and snapshot is configured"
    echo "Using specified snapshot: $SNAPSHOT"
    if ! download_and_extract_snapshot "$SNAPSHOT"; then
      echo "❌ Snapshot download/extraction failed. Will continue without snapshot..."
      echo "The node will sync from genesis (this will take much longer)"
    fi
  elif [ "$DATA_FILE_COUNT" -eq 0 ] && [ -n "${SNAPSHOT_API_URL:-}" ] && [ -n "${SNAPSHOT_BASE_URL:-}" ]; then
    echo "Data directory is minimal, fetching latest snapshot automatically..."
    CHAIN_PREFIX=$(echo "$SNAPSHOT_API_URL" | grep -oE 'prefix=[^&]*' | cut -d'=' -f2 || echo "$DAEMON_NAME")
    FILENAME=$(curl -s "$SNAPSHOT_API_URL" | grep -Eo "${CHAIN_PREFIX}/[0-9]+.tar.gz" | sort -n | tail -n 1 | cut -d "/" -f 2)
    if [ -n "$FILENAME" ]; then
      echo "Using latest snapshot: $FILENAME"
      if ! download_and_extract_snapshot "${SNAPSHOT_BASE_URL}${FILENAME}"; then
        echo "❌ Snapshot download/extraction failed. Will continue without snapshot..."
        echo "The node will sync from genesis (this will take much longer)"
      fi
      echo "✅ Snapshot extraction completed successfully!"
    else
      echo "No snapshot found, will start syncing from genesis block 1..."
    fi
  else
    echo "Will start syncing from genesis block 1..."
  fi
fi

echo "✅ Initialization completed!"

sleep 5000

# Validate that genesis file exists and is readable
GENESIS_FILE="${BLOCKCHAIN_HOME}/config/genesis.json"
if [ ! -f "$GENESIS_FILE" ]; then
  echo "ERROR: Genesis file not found at $GENESIS_FILE"
  echo "Available files in config directory:"
  ls -la ${BLOCKCHAIN_HOME}/config/ || echo "Config directory not accessible"
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
echo "Home: ${BLOCKCHAIN_HOME}"
echo "Version: $NODE_VERSION"

# Build the command with configured flags
CMD="${DAEMON_NAME} start --home ${BLOCKCHAIN_HOME}"

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

# Function to download, decompress, extract, and clean up snapshot
# Usage: download_and_extract_snapshot <snapshot_url>
download_and_extract_snapshot() {
  local SNAP_URL="$1"
  local FILENAME FILEPATH
  FILENAME=$(basename "$SNAP_URL")
  echo "Downloading snapshot: $SNAP_URL"
  aria2c --split=16 --max-concurrent-downloads=16 --max-connection-per-server=16 --continue --min-split-size=100M -d ${BLOCKCHAIN_HOME} -o "$FILENAME" "$SNAP_URL"
  FILEPATH="${BLOCKCHAIN_HOME}/$FILENAME"
  if [[ "$FILENAME" == *.tar.lz4 ]]; then
    echo "Decompressing LZ4 archive..."
    lz4 -c -d "$FILEPATH" > "${BLOCKCHAIN_HOME}/snapshot.tar"
    rm "$FILEPATH"
  elif [[ "$FILENAME" == *.tar.gz ]]; then
    echo "Decompressing GZ archive..."
    gzip -d -c "$FILEPATH" > "${BLOCKCHAIN_HOME}/snapshot.tar"
    rm "$FILEPATH"
  elif [[ "$FILENAME" == *.tar.zst ]]; then
    echo "Decompressing ZST archive..."
    zstd -d -c "$FILEPATH" > "${BLOCKCHAIN_HOME}/snapshot.tar"
    rm "$FILEPATH"
  else
    echo "Unsupported snapshot format: $FILENAME"
    rm -f "$FILEPATH"
    return 1
  fi
  echo "Extracting tarball..."
  tar --exclude='data/priv_validator_state.json' -xvf "${BLOCKCHAIN_HOME}/snapshot.tar" -C ${BLOCKCHAIN_HOME}
  rm "${BLOCKCHAIN_HOME}/snapshot.tar"
  echo "✅ Snapshot extraction completed successfully!"
}

