#!/bin/bash

# THORChain Node Monitoring Script

set -e

RPC_URL="http://localhost:27147"

echo "=== THORChain Node Status ==="
echo "Timestamp: $(date)"
echo ""

# Check if node is responding
if ! curl -s "$RPC_URL/status" > /dev/null; then
    echo "❌ Node is not responding on $RPC_URL"
    exit 1
fi

# Get node status
STATUS=$(curl -s "$RPC_URL/status")

# Parse key information
CATCHING_UP=$(echo "$STATUS" | jq -r '.result.sync_info.catching_up')
LATEST_BLOCK_HEIGHT=$(echo "$STATUS" | jq -r '.result.sync_info.latest_block_height')
LATEST_BLOCK_TIME=$(echo "$STATUS" | jq -r '.result.sync_info.latest_block_time')
NODE_ID=$(echo "$STATUS" | jq -r '.result.node_info.id')
MONIKER=$(echo "$STATUS" | jq -r '.result.node_info.moniker')
VERSION=$(echo "$STATUS" | jq -r '.result.node_info.version')

echo "Node ID: $NODE_ID"
echo "Moniker: $MONIKER"
echo "Version: $VERSION"
echo "Latest Block: $LATEST_BLOCK_HEIGHT"
echo "Latest Block Time: $LATEST_BLOCK_TIME"
echo "Catching Up: $CATCHING_UP"

if [ "$CATCHING_UP" = "false" ]; then
    echo "✅ Node is synced"
else
    echo "🔄 Node is syncing"
fi

# Get peer count
PEERS=$(curl -s "$RPC_URL/net_info" | jq -r '.result.n_peers')
echo "Connected Peers: $PEERS"

echo ""
echo "=== Health Check Complete ==="
