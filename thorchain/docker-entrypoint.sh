#!/usr/bin/env bash
set -euo pipefail

# Ensure bin directory exists and copy the binary from builds (always do this)
mkdir -p /thornode/bin
cp /builds/thornode-${THORNODE_VERSION} /thornode/bin/thornode
chmod +x /thornode/bin/thornode

if [[ ! -f /thornode/.initialized ]]; then
  echo "Initializing THORNode!"

  echo "Running init..."
  /thornode/bin/thornode init $MONIKER --chain-id $NETWORK --home /thornode --overwrite

  echo "Downloading genesis file..."
  if [ -n "${GENESIS_URL:-}" ]; then
    echo "Using configured genesis URL: $GENESIS_URL"
    curl "$GENESIS_URL" -o /thornode/config/genesis.json
  else
    echo "No genesis URL configured, using default..."
    curl https://storage.googleapis.com/public-snapshots-ninerealms/genesis/17562000.json -o /thornode/config/genesis.json
  fi

  if [ -n "$SNAPSHOT" ]; then
    echo "Using specified snapshot: $SNAPSHOT"
    if [[ "$SNAPSHOT" == *.tar.lz4 ]]; then
      echo "Downloading and extracting LZ4 snapshot..."
      curl -o - -L "$SNAPSHOT" | lz4 -c -d - | tar --exclude='data/priv_validator_state.json' -xv -C /thornode
      echo "LZ4 snapshot extraction completed successfully!"
    elif [[ "$SNAPSHOT" == *.tar.gz ]]; then
      echo "Downloading and extracting GZ snapshot..."
      curl -o - -L "$SNAPSHOT" | tar --exclude='data/priv_validator_state.json' -xzvf - -C /thornode
      echo "GZ snapshot extraction completed successfully!"
    else
      echo "Unsupported snapshot format: $SNAPSHOT"
      exit 1
    fi
  else
    echo "Fetching latest snapshot automatically..."
    SNAPSHOT_API_URL="${SNAPSHOT_API_URL:-https://snapshots.ninerealms.com/snapshots?prefix=thornode}"
    SNAPSHOT_BASE_URL="${SNAPSHOT_BASE_URL:-https://snapshots.ninerealms.com/snapshots/thornode/}"
    
    FILENAME=$(curl -s "$SNAPSHOT_API_URL" | grep -Eo "thornode/[0-9]+.tar.gz" | sort -n | tail -n 1 | cut -d "/" -f 2)
    if [ -n "$FILENAME" ]; then
      echo "Using latest snapshot: $FILENAME"
      aria2c --split=16 --max-concurrent-downloads=16 --max-connection-per-server=16 --continue --min-split-size=100M -d /thornode -o $FILENAME "${SNAPSHOT_BASE_URL}${FILENAME}"
      echo "Download completed. Preparing to extract snapshot..."
      rm -rf /thornode/data/*.db /thornode/data/snapshot /thornode/data/cs.wal
      
      # Show file size and start extraction with progress monitoring
      FILESIZE=$(du -h /thornode/$FILENAME | cut -f1)
      echo "Download completed. Preparing to extract snapshot..." >&1
      echo "Extracting snapshot ($FILESIZE) - this may take several minutes..." >&1
      echo "Starting extraction at $(date)" >&1
      
      # Start extraction in background and monitor progress
      tar -xzf /thornode/$FILENAME -C /thornode --exclude "*_state.json" &
      TAR_PID=$!
      
      echo "Extraction process started (PID: $TAR_PID)" >&1
      
      # Monitor extraction progress
      while kill -0 $TAR_PID 2>/dev/null; do
        if [ -d "/thornode/data" ]; then
          DATA_SIZE=$(du -sh /thornode/data 2>/dev/null | cut -f1 || echo "0")
          echo "Extraction in progress... Data directory size: $DATA_SIZE ($(date))" >&1
        else
          echo "Extraction starting... ($(date))" >&1
        fi
        sleep 30
      done
      
      wait $TAR_PID
      EXTRACT_EXIT_CODE=$?
      
      if [ $EXTRACT_EXIT_CODE -eq 0 ]; then
        echo "Snapshot extraction completed successfully at $(date)!" >&1
        rm -rf /thornode/$FILENAME
        echo "Cleanup completed. THORNode data is ready." >&1
      else
        echo "ERROR: Snapshot extraction failed with exit code $EXTRACT_EXIT_CODE" >&2
        exit 1
      fi
    else
      echo "Could not find latest snapshot. Node will sync from genesis."
    fi
  fi

  touch /thornode/.initialized
else
  echo "Already initialized!"
  # Still copy the binary in case of updates
  mkdir -p /thornode/bin
  cp /builds/thornode-${THORNODE_VERSION} /thornode/bin/thornode
  chmod +x /thornode/bin/thornode
fi

# Configure all settings every time (not just during initialization)
echo "Configuring THORNode settings..."

# Configure basic node settings
echo "Configuring basic node settings..."
dasel put -f /thornode/config/config.toml -v "${PROXY_APP:-tcp://127.0.0.1:26658}" proxy_app
dasel put -f /thornode/config/config.toml -v "${FAST_SYNC:-true}" fast_sync
dasel put -f /thornode/config/config.toml -v "${LOG_FORMAT:-plain}" log_format

# Configure seed nodes
if [ -n "${SEEDS:-}" ]; then
  echo "Using configured seeds: $SEEDS"
  dasel put -f /thornode/config/config.toml -v "$SEEDS" p2p.seeds
else
  echo "WARNING: No seeds configured in environment variables!"
  echo "Node may have difficulty finding peers. Please set SEEDS in .env file."
fi

# Configure persistent peers (run every time to ensure they're applied)
if [ -n "${PERSISTENT_PEERS:-}" ]; then
  echo "Configuring persistent peers: $PERSISTENT_PEERS"
  dasel put -f /thornode/config/config.toml -v "$PERSISTENT_PEERS" p2p.persistent_peers
fi

# Configure P2P connection limits (run every time to ensure they're applied)
echo "Configuring P2P connection limits..."
dasel put -f /thornode/config/config.toml -v "${MAX_INBOUND_PEERS:-40}" p2p.max_num_inbound_peers
dasel put -f /thornode/config/config.toml -v "${MAX_OUTBOUND_PEERS:-10}" p2p.max_num_outbound_peers

# Configure P2P optimizations (run every time to ensure they're applied)
echo "Configuring P2P optimizations..."
dasel put -f /thornode/config/config.toml -v "${P2P_PEX:-true}" p2p.pex
dasel put -f /thornode/config/config.toml -v "${P2P_ADDR_BOOK_STRICT:-false}" p2p.addr_book_strict
dasel put -f /thornode/config/config.toml -v "${P2P_FLUSH_THROTTLE_TIMEOUT:-100ms}" p2p.flush_throttle_timeout
dasel put -f /thornode/config/config.toml -v "${P2P_DIAL_TIMEOUT:-3s}" p2p.dial_timeout
dasel put -f /thornode/config/config.toml -v "${P2P_HANDSHAKE_TIMEOUT:-20s}" p2p.handshake_timeout
dasel put -f /thornode/config/config.toml -v "${P2P_ALLOW_DUPLICATE_IP:-true}" p2p.allow_duplicate_ip

# Configure RPC settings
echo "Configuring RPC settings..."
dasel put -f /thornode/config/config.toml -v "${RPC_CORS_ALLOWED_ORIGINS:-[\"*\"]}" rpc.cors_allowed_origins
dasel put -f /thornode/config/config.toml -v "${RPC_MAX_OPEN_CONNECTIONS:-900}" rpc.max_open_connections
dasel put -f /thornode/config/config.toml -v "${RPC_GRPC_MAX_OPEN_CONNECTIONS:-900}" rpc.grpc_max_open_connections

# Configure State Sync settings
echo "Configuring State Sync settings..."
dasel put -f /thornode/config/config.toml -v "${STATESYNC_ENABLE:-false}" statesync.enable
if [ -n "${STATESYNC_RPC_SERVERS:-}" ]; then
  dasel put -f /thornode/config/config.toml -v "$STATESYNC_RPC_SERVERS" statesync.rpc_servers
fi
dasel put -f /thornode/config/config.toml -v "${STATESYNC_TRUST_PERIOD:-360h0m0s}" statesync.trust_period

# Configure Consensus settings
echo "Configuring Consensus settings..."
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_TIMEOUT_COMMIT:-5s}" consensus.timeout_commit
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_CREATE_EMPTY_BLOCKS:-true}" consensus.create_empty_blocks

# Configure Mempool settings
echo "Configuring Mempool settings..."
dasel put -f /thornode/config/config.toml -v "${MEMPOOL_SIZE:-5000}" mempool.size
dasel put -f /thornode/config/config.toml -v "${MEMPOOL_CACHE_SIZE:-10000}" mempool.cache_size

# Configure Instrumentation settings
echo "Configuring Instrumentation settings..."
dasel put -f /thornode/config/config.toml -v "${PROMETHEUS_ENABLED:-true}" instrumentation.prometheus
dasel put -f /thornode/config/config.toml -v "${PROMETHEUS_NAMESPACE:-tendermint}" instrumentation.namespace

# Configure additional P2P settings for optimal performance
echo "Configuring additional P2P settings..."
dasel put -f /thornode/config/config.toml -v "${P2P_SEND_RATE:-5120000}" p2p.send_rate
dasel put -f /thornode/config/config.toml -v "${P2P_RECV_RATE:-5120000}" p2p.recv_rate
dasel put -f /thornode/config/config.toml -v "${P2P_MAX_PACKET_MSG_PAYLOAD_SIZE:-1024}" p2p.max_packet_msg_payload_size
dasel put -f /thornode/config/config.toml -v "${P2P_SEED_MODE:-false}" p2p.seed_mode
dasel put -f /thornode/config/config.toml -v "${P2P_UNCONDITIONAL_PEER_IDS:-}" p2p.unconditional_peer_ids
dasel put -f /thornode/config/config.toml -v "${P2P_PERSISTENT_PEERS_MAX_DIAL_PERIOD:-0s}" p2p.persistent_peers_max_dial_period

# Configure additional mempool settings
echo "Configuring additional mempool settings..."
dasel put -f /thornode/config/config.toml -v "${MEMPOOL_RECHECK:-true}" mempool.recheck
dasel put -f /thornode/config/config.toml -v "${MEMPOOL_BROADCAST:-true}" mempool.broadcast
dasel put -f /thornode/config/config.toml -v "${MEMPOOL_MAX_TXS_BYTES:-1073741824}" mempool.max_txs_bytes
dasel put -f /thornode/config/config.toml -v "${MEMPOOL_MAX_TX_BYTES:-1048576}" mempool.max_tx_bytes
dasel put -f /thornode/config/config.toml -v "${MEMPOOL_MAX_BATCH_BYTES:-0}" mempool.max_batch_bytes
dasel put -f /thornode/config/config.toml -v "${MEMPOOL_KEEP_INVALID_TXS:-false}" mempool.keep-invalid-txs-in-cache

# Configure additional consensus settings
echo "Configuring additional consensus settings..."
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_TIMEOUT_PROPOSE:-3s}" consensus.timeout_propose
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_TIMEOUT_PROPOSE_DELTA:-500ms}" consensus.timeout_propose_delta
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_TIMEOUT_PREVOTE:-1s}" consensus.timeout_prevote
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_TIMEOUT_PREVOTE_DELTA:-500ms}" consensus.timeout_prevote_delta
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_TIMEOUT_PRECOMMIT:-1s}" consensus.timeout_precommit
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_TIMEOUT_PRECOMMIT_DELTA:-500ms}" consensus.timeout_precommit_delta
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_SKIP_TIMEOUT_COMMIT:-false}" consensus.skip_timeout_commit
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_CREATE_EMPTY_BLOCKS_INTERVAL:-0s}" consensus.create_empty_blocks_interval
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_PEER_GOSSIP_SLEEP_DURATION:-100ms}" consensus.peer_gossip_sleep_duration
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_PEER_QUERY_MAJ23_SLEEP_DURATION:-2s}" consensus.peer_query_maj23_sleep_duration
dasel put -f /thornode/config/config.toml -v "${CONSENSUS_DOUBLE_SIGN_CHECK_HEIGHT:-0}" consensus.double_sign_check_height

# Configure additional RPC settings
echo "Configuring additional RPC settings..."
dasel put -f /thornode/config/config.toml -v "${RPC_CORS_ALLOWED_METHODS:-[\"HEAD\", \"GET\", \"POST\"]}" rpc.cors_allowed_methods
dasel put -f /thornode/config/config.toml -v "${RPC_CORS_ALLOWED_HEADERS:-[\"Origin\", \"Accept\", \"Content-Type\", \"X-Requested-With\", \"X-Server-Time\"]}" rpc.cors_allowed_headers
dasel put -f /thornode/config/config.toml -v "${RPC_UNSAFE:-false}" rpc.unsafe
dasel put -f /thornode/config/config.toml -v "${RPC_MAX_SUBSCRIPTION_CLIENTS:-100}" rpc.max_subscription_clients
dasel put -f /thornode/config/config.toml -v "${RPC_MAX_SUBSCRIPTIONS_PER_CLIENT:-5}" rpc.max_subscriptions_per_client
dasel put -f /thornode/config/config.toml -v "${RPC_EXPERIMENTAL_SUBSCRIPTION_BUFFER_SIZE:-200}" rpc.experimental_subscription_buffer_size
dasel put -f /thornode/config/config.toml -v "${RPC_EXPERIMENTAL_WEBSOCKET_WRITE_BUFFER_SIZE:-200}" rpc.experimental_websocket_write_buffer_size
dasel put -f /thornode/config/config.toml -v "${RPC_EXPERIMENTAL_CLOSE_ON_SLOW_CLIENT:-false}" rpc.experimental_close_on_slow_client
dasel put -f /thornode/config/config.toml -v "${RPC_TIMEOUT_BROADCAST_TX_COMMIT:-10s}" rpc.timeout_broadcast_tx_commit
dasel put -f /thornode/config/config.toml -v "${RPC_MAX_BODY_BYTES:-1000000}" rpc.max_body_bytes
dasel put -f /thornode/config/config.toml -v "${RPC_MAX_HEADER_BYTES:-1048576}" rpc.max_header_bytes

# Configure additional State Sync settings
echo "Configuring additional State Sync settings..."
dasel put -f /thornode/config/config.toml -v "${STATESYNC_TRUST_HEIGHT:-0}" statesync.trust_height
dasel put -f /thornode/config/config.toml -v "${STATESYNC_TRUST_HASH:-}" statesync.trust_hash
dasel put -f /thornode/config/config.toml -v "${STATESYNC_DISCOVERY_TIME:-15s}" statesync.discovery_time
dasel put -f /thornode/config/config.toml -v "${STATESYNC_CHUNK_REQUEST_TIMEOUT:-10s}" statesync.chunk_request_timeout
dasel put -f /thornode/config/config.toml -v "${STATESYNC_CHUNK_FETCHERS:-4}" statesync.chunk_fetchers

# Configure additional instrumentation settings
echo "Configuring additional instrumentation settings..."
dasel put -f /thornode/config/config.toml -v "${PROMETHEUS_LISTEN_ADDR:-:26660}" instrumentation.prometheus_listen_addr
dasel put -f /thornode/config/config.toml -v "${PROMETHEUS_MAX_OPEN_CONNECTIONS:-3}" instrumentation.max_open_connections

# Configure FastSync settings
echo "Configuring FastSync settings..."
dasel put -f /thornode/config/config.toml -v "${FASTSYNC_VERSION:-v0}" fastsync.version

# Configure tx_index settings
echo "Configuring TX Index settings..."
dasel put -f /thornode/config/config.toml -v "${TX_INDEX_INDEXER:-kv}" tx_index.indexer

# Configure basic node settings (that might not be set by default)
echo "Configuring additional basic node settings..."
dasel put -f /thornode/config/config.toml -v "${DB_BACKEND:-goleveldb}" db_backend
dasel put -f /thornode/config/config.toml -v "${DB_DIR:-data}" db_dir
dasel put -f /thornode/config/config.toml -v "${ABCI:-socket}" abci
dasel put -f /thornode/config/config.toml -v "${FILTER_PEERS:-false}" filter_peers

echo "P2P addr_book_strict: $(dasel -f /thornode/config/config.toml p2p.addr_book_strict)"
echo "P2P allow_duplicate_ip: $(dasel -f /thornode/config/config.toml p2p.allow_duplicate_ip)"
echo "P2P handshake_timeout: $(dasel -f /thornode/config/config.toml p2p.handshake_timeout)"

# Configure private peer IDs (trusted peers) if provided
if [ -n "${PRIVATE_PEER_IDS:-}" ]; then
  echo "Configuring private peer IDs (trusted peers): $PRIVATE_PEER_IDS"
  dasel put -f /thornode/config/config.toml -v "$PRIVATE_PEER_IDS" p2p.private_peer_ids
fi

# Configure external address if provided
if [ -n "${EXTERNAL_ADDRESS:-}" ]; then
  if [ "$EXTERNAL_ADDRESS" = "auto" ]; then
    echo "Auto-detecting external IP address..."
    DETECTED_IP=$(curl -s --connect-timeout 10 ifconfig.me -4 || echo "")
    if [ -n "$DETECTED_IP" ]; then
      EXTERNAL_ADDRESS="${DETECTED_IP}:${P2P_PORT:-27146}"
      echo "Detected external IP: $DETECTED_IP, using external address: $EXTERNAL_ADDRESS"
    else
      echo "WARNING: Failed to auto-detect external IP. External address will not be configured."
      EXTERNAL_ADDRESS=""
    fi
  fi
  
  if [ -n "$EXTERNAL_ADDRESS" ]; then
    echo "Configuring external address: $EXTERNAL_ADDRESS"
    dasel put -f /thornode/config/config.toml -v "$EXTERNAL_ADDRESS" p2p.external_address
  fi
fi

# Configure P2P and RPC ports
if [ -n "${P2P_PORT}" ]; then
  echo "Setting P2P port to: ${P2P_PORT}"
  dasel put -f /thornode/config/config.toml -v "tcp://0.0.0.0:${P2P_PORT}" p2p.laddr
fi

if [ -n "${RPC_PORT}" ]; then
  echo "Setting RPC port to: ${RPC_PORT}"
  dasel put -f /thornode/config/config.toml -v "tcp://0.0.0.0:${RPC_PORT}" rpc.laddr
fi

# Update app.toml for REST API and gRPC (run every time)
echo "Configuring API and gRPC settings..."
dasel put -f /thornode/config/app.toml -v true grpc.enable 2>/dev/null || true
dasel put -f /thornode/config/app.toml -v "0.0.0.0:${GRPC_PORT:-9090}" grpc.address 2>/dev/null || true
dasel put -f /thornode/config/app.toml -v true grpc-web.enable 2>/dev/null || true
dasel put -f /thornode/config/app.toml -v "0.0.0.0:${GRPC_WEB_PORT:-9091}" grpc-web.address 2>/dev/null || true
dasel put -f /thornode/config/app.toml -v "tcp://0.0.0.0:${REST_PORT}" api.address
dasel put -f /thornode/config/app.toml -v true api.enable

echo "Starting THORNode..."
exec /thornode/bin/thornode start --home /thornode --grpc.address=0.0.0.0:${GRPC_PORT:-9090}
