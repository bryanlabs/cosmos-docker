#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f /thornode/.initialized ]]; then
  echo "Initializing THORNode!"

  # Ensure bin directory exists and copy the binary from builds
  mkdir -p /thornode/bin
  cp /builds/thornode-${THORNODE_VERSION} /thornode/bin/thornode
  chmod +x /thornode/bin/thornode

  echo "Running init..."
  /thornode/bin/thornode init $MONIKER --chain-id $NETWORK --home /thornode --overwrite

  echo "Configuring seed nodes..."
  if [ -n "${SEEDS:-}" ]; then
    echo "Using configured seeds: $SEEDS"
    dasel put -f /thornode/config/config.toml -v "$SEEDS" p2p.seeds
  else
    echo "WARNING: No seeds configured in environment variables!"
    echo "Node may have difficulty finding peers. Please set SEEDS in .env file."
  fi

  # Configure persistent peers for faster sync
  if [ -n "${PERSISTENT_PEERS:-}" ]; then
    echo "Configuring persistent peers: $PERSISTENT_PEERS"
    dasel put -f /thornode/config/config.toml -v "$PERSISTENT_PEERS" p2p.persistent_peers
  fi

  # Configure P2P connection limits for faster sync
  echo "Configuring P2P connection limits..."
  dasel put -f /thornode/config/config.toml -v "${MAX_INBOUND_PEERS:-400}" p2p.max_num_inbound_peers
  dasel put -f /thornode/config/config.toml -v "${MAX_OUTBOUND_PEERS:-400}" p2p.max_num_outbound_peers
  
  # Additional P2P optimizations for faster sync
  dasel put -f /thornode/config/config.toml -v "${P2P_PEX:-true}" p2p.pex
  dasel put -f /thornode/config/config.toml -v "${P2P_ADDR_BOOK_STRICT:-true}" p2p.addr_book_strict
  dasel put -f /thornode/config/config.toml -v "${P2P_FLUSH_THROTTLE_TIMEOUT:-30s}" p2p.flush_throttle_timeout
  dasel put -f /thornode/config/config.toml -v "${P2P_DIAL_TIMEOUT:-10s}" p2p.dial_timeout
  dasel put -f /thornode/config/config.toml -v "${P2P_HANDSHAKE_TIMEOUT:-3s}" p2p.handshake_timeout
  dasel put -f /thornode/config/config.toml -v "${P2P_ALLOW_DUPLICATE_IP:-false}" p2p.allow_duplicate_ip

  # Configure external address if provided
  if [ -n "${EXTERNAL_ADDRESS:-}" ]; then
    echo "Configuring external address: $EXTERNAL_ADDRESS"
    dasel put -f /thornode/config/config.toml -v "$EXTERNAL_ADDRESS" p2p.external_address
  fi

  echo "Adjusting ports to THORNode standards..."
  # Update RPC port
  dasel put -f /thornode/config/config.toml -v "tcp://0.0.0.0:${RPC_PORT}" rpc.laddr
  # Update P2P port
  dasel put -f /thornode/config/config.toml -v "tcp://0.0.0.0:${P2P_PORT}" p2p.laddr
  
  # Update app.toml for REST API and gRPC
  # Enable gRPC with correct address format
  dasel put -f /thornode/config/app.toml -v true grpc.enable 2>/dev/null || true
  dasel put -f /thornode/config/app.toml -v "0.0.0.0:${GRPC_PORT:-9090}" grpc.address 2>/dev/null || true
  dasel put -f /thornode/config/app.toml -v true grpc-web.enable 2>/dev/null || true
  dasel put -f /thornode/config/app.toml -v "0.0.0.0:${GRPC_WEB_PORT:-9091}" grpc-web.address 2>/dev/null || true
  
  dasel put -f /thornode/config/app.toml -v "tcp://0.0.0.0:${REST_PORT}" api.address
  dasel put -f /thornode/config/app.toml -v true api.enable

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

# Configure seeds if provided
if [ -n "${SEEDS}" ]; then
  echo "Configuring seeds: ${SEEDS}"
  sed -i "s/seeds = '.*'/seeds = '${SEEDS}'/" /thornode/config/config.toml
fi

# Configure persistent peers (run every time to ensure they're applied)
if [ -n "${PERSISTENT_PEERS:-}" ]; then
  echo "Configuring persistent peers: $PERSISTENT_PEERS"
  dasel put -f /thornode/config/config.toml -v "$PERSISTENT_PEERS" p2p.persistent_peers
fi

# Configure P2P connection limits (run every time to ensure they're applied)
echo "Configuring P2P connection limits..."
dasel put -f /thornode/config/config.toml -v "${MAX_INBOUND_PEERS:-400}" p2p.max_num_inbound_peers
dasel put -f /thornode/config/config.toml -v "${MAX_OUTBOUND_PEERS:-400}" p2p.max_num_outbound_peers

# Configure P2P optimizations (run every time to ensure they're applied)
echo "Configuring P2P optimizations..."
dasel put -f /thornode/config/config.toml -v "${P2P_PEX:-true}" p2p.pex
dasel put -f /thornode/config/config.toml -v "${P2P_ADDR_BOOK_STRICT:-true}" p2p.addr_book_strict
dasel put -f /thornode/config/config.toml -v "${P2P_FLUSH_THROTTLE_TIMEOUT:-30s}" p2p.flush_throttle_timeout
dasel put -f /thornode/config/config.toml -v "${P2P_DIAL_TIMEOUT:-10s}" p2p.dial_timeout
dasel put -f /thornode/config/config.toml -v "${P2P_HANDSHAKE_TIMEOUT:-3s}" p2p.handshake_timeout
dasel put -f /thornode/config/config.toml -v "${P2P_ALLOW_DUPLICATE_IP:-false}" p2p.allow_duplicate_ip

# Configure private peer IDs (trusted peers) if provided
if [ -n "${PRIVATE_PEER_IDS:-}" ]; then
  echo "Configuring private peer IDs (trusted peers): $PRIVATE_PEER_IDS"
  dasel put -f /thornode/config/config.toml -v "$PRIVATE_PEER_IDS" p2p.private_peer_ids
fi

# Configure external address if provided
if [ -n "${EXTERNAL_ADDRESS:-}" ]; then
  echo "Configuring external address: $EXTERNAL_ADDRESS"
  dasel put -f /thornode/config/config.toml -v "$EXTERNAL_ADDRESS" p2p.external_address
fi

# Configure P2P and RPC ports
if [ -n "${P2P_PORT}" ]; then
  echo "Setting P2P port to: ${P2P_PORT}"
  sed -i "s/laddr = \"tcp:\/\/0.0.0.0:26656\"/laddr = \"tcp:\/\/0.0.0.0:${P2P_PORT}\"/" /thornode/config/config.toml
fi

if [ -n "${RPC_PORT}" ]; then
  echo "Setting RPC port to: ${RPC_PORT}"
  sed -i "s/laddr = \"tcp:\/\/127.0.0.1:26657\"/laddr = \"tcp:\/\/0.0.0.0:${RPC_PORT}\"/" /thornode/config/config.toml
fi

echo "Starting THORNode..."
exec /thornode/bin/thornode start --home /thornode --grpc.address=0.0.0.0:${GRPC_PORT:-9090}
