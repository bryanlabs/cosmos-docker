#!/usr/bin/env bash

# Test script to verify minimum gas price and pruning configuration

echo "=== Testing Environment Configuration ==="
echo ""

# Source the .env file to get variables
if [ -f .env ]; then
    echo "📋 Loading .env configuration..."
    set -a
    source .env
    set +a
    echo "✅ .env loaded successfully"
else
    echo "❌ .env file not found"
    exit 1
fi

echo ""
echo "🔧 Current Environment Variables:"
echo "MIN_GAS_PRICE: ${MIN_GAS_PRICE:-not set}"
echo "PRUNING_STRATEGY: ${PRUNING_STRATEGY:-not set}"
echo "PRUNING_KEEP_RECENT: ${PRUNING_KEEP_RECENT:-not set}"
echo "PRUNING_INTERVAL: ${PRUNING_INTERVAL:-not set}"
echo "EXTRA_FLAGS: ${EXTRA_FLAGS:-not set}"

echo ""
echo "🧪 Testing what would be passed to the daemon:"

# Simulate the entrypoint script logic
CMD="${DAEMON_NAME:-gaiad} start --home ${DAEMON_HOME:-/gaiad}"

if [ -n "${MIN_GAS_PRICE:-}" ]; then
    echo "Would add minimum gas price flag: --minimum-gas-prices=$MIN_GAS_PRICE"
    CMD="$CMD --minimum-gas-prices=$MIN_GAS_PRICE"
fi

if [ -n "${PRUNING_STRATEGY:-}" ]; then
    echo "Would add pruning strategy flag: --pruning=$PRUNING_STRATEGY"
    CMD="$CMD --pruning=$PRUNING_STRATEGY"
    
    if [ "$PRUNING_STRATEGY" = "custom" ]; then
        if [ -n "${PRUNING_KEEP_RECENT:-}" ]; then
            echo "Would add pruning keep recent flag: --pruning-keep-recent=$PRUNING_KEEP_RECENT"
            CMD="$CMD --pruning-keep-recent=$PRUNING_KEEP_RECENT"
        fi
        
        if [ -n "${PRUNING_INTERVAL:-}" ]; then
            echo "Would add pruning interval flag: --pruning-interval=$PRUNING_INTERVAL"
            CMD="$CMD --pruning-interval=$PRUNING_INTERVAL"
        fi
    fi
fi

if [ -n "${EXTRA_FLAGS:-}" ]; then
    echo "Would add extra flags: $EXTRA_FLAGS"
    CMD="$CMD $EXTRA_FLAGS"
fi

echo ""
echo "🚀 Final command that would be executed:"
echo "$CMD"

echo ""
echo "✅ Configuration test completed!"
