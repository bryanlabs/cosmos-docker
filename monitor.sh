#!/bin/bash

# Cosmos Chain Node Monitoring Script

set -e

# Read RPC port from .env file or use default
if [ -f .env ]; then
    RPC_PORT=$(grep "^RPC_PORT=" .env | cut -d'=' -f2 | head -1)
fi
RPC_PORT=${RPC_PORT:-26657}  # Default to 26657 if not found

# Configuration
RPC_URL="http://localhost:${RPC_PORT}"
TIMEOUT=10

echo "=== Cosmos Node Status ==="
echo "Timestamp: $(date)"
echo "RPC URL: $RPC_URL"
echo ""

# Function to check if jq is available
check_jq() {
    if ! command -v jq &> /dev/null; then
        echo "❌ jq is not installed. Please install jq to use this monitoring script."
        echo "   Ubuntu/Debian: sudo apt-get install jq"
        echo "   CentOS/RHEL: sudo yum install jq"
        echo "   macOS: brew install jq"
        exit 1
    fi
}

# Function to check if curl is available
check_curl() {
    if ! command -v curl &> /dev/null; then
        echo "❌ curl is not installed. Please install curl to use this monitoring script."
        exit 1
    fi
}

# Check dependencies
check_jq
check_curl

# Check if node is responding
echo "🔍 Checking node connectivity..."
if ! curl -s --connect-timeout $TIMEOUT "$RPC_URL/status" > /dev/null; then
    echo "❌ Node is not responding on $RPC_URL"
    echo "   • Check if the node is running: docker compose ps"
    echo "   • Check logs: docker compose logs cosmos"
    echo "   • Verify port configuration in .env file"
    exit 1
fi

echo "✅ Node is responding"
echo ""

# Get node status with error handling
echo "📊 Fetching node status..."
STATUS=$(curl -s --connect-timeout $TIMEOUT "$RPC_URL/status" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$STATUS" ]; then
    echo "❌ Failed to fetch node status"
    exit 1
fi

# Parse key information with error handling
echo "📈 Parsing node information..."
CATCHING_UP=$(echo "$STATUS" | jq -r '.result.sync_info.catching_up // "unknown"')
LATEST_BLOCK_HEIGHT=$(echo "$STATUS" | jq -r '.result.sync_info.latest_block_height // "unknown"')
LATEST_BLOCK_TIME=$(echo "$STATUS" | jq -r '.result.sync_info.latest_block_time // "unknown"')
NODE_ID=$(echo "$STATUS" | jq -r '.result.node_info.id // "unknown"')
MONIKER=$(echo "$STATUS" | jq -r '.result.node_info.moniker // "unknown"')
VERSION=$(echo "$STATUS" | jq -r '.result.node_info.version // "unknown"')

echo "Node ID: $NODE_ID"
echo "Moniker: $MONIKER"
echo "Version: $VERSION"
echo "Latest Block: $LATEST_BLOCK_HEIGHT"
echo "Latest Block Time: $LATEST_BLOCK_TIME"
echo "Catching Up: $CATCHING_UP"

if [ "$CATCHING_UP" = "false" ]; then
    echo "✅ Node is synced"
elif [ "$CATCHING_UP" = "true" ]; then
    echo "🔄 Node is syncing"
else
    echo "⚠️  Node sync status unknown"
fi

# Get peer count with error handling
echo ""
echo "🌐 Checking network connectivity..."
PEERS_RESULT=$(curl -s --connect-timeout $TIMEOUT "$RPC_URL/net_info" 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$PEERS_RESULT" ]; then
    PEERS=$(echo "$PEERS_RESULT" | jq -r '.result.n_peers // "unknown"')
    echo "Connected Peers: $PEERS"
    
    if [ "$PEERS" != "unknown" ] && [ "$PEERS" -gt 0 ]; then
        echo "✅ Connected to $PEERS peers"
    elif [ "$PEERS" = "0" ]; then
        echo "⚠️  No peers connected - node may have connectivity issues"
    fi
else
    echo "⚠️  Could not fetch peer information"
fi

echo ""
echo "=== Health Check Complete ==="
