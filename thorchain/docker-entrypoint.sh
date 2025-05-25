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
  dasel put -f /thornode/config/config.toml -v "c3613862c2608b3e861406ad02146f41cf5124e6@statesync-seed.ninerealms.com:27146,dbd1730bff1e8a21aad93bc6083209904d483185@statesync-seed-2.ninerealms.com:27146" p2p.seeds

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
  curl https://storage.googleapis.com/public-snapshots-ninerealms/genesis/17562000.json -o /thornode/config/genesis.json

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
    FILENAME=$(curl -s "https://snapshots.ninerealms.com/snapshots?prefix=thornode" | grep -Eo "thornode/[0-9]+.tar.gz" | sort -n | tail -n 1 | cut -d "/" -f 2)
    if [ -n "$FILENAME" ]; then
      echo "Using latest snapshot: $FILENAME"
      aria2c --split=16 --max-concurrent-downloads=16 --max-connection-per-server=16 --continue --min-split-size=100M -d /thornode -o $FILENAME "https://snapshots.ninerealms.com/snapshots/thornode/${FILENAME}"
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

echo "Starting THORNode..."
exec /thornode/bin/thornode start --home /thornode --grpc.address=0.0.0.0:${GRPC_PORT:-9090}
