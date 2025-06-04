#!/bin/bash
# Chain Manager - Manage chain configurations for cosmos-docker
# Usage: ./scripts/chain-manager.sh [command] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
CHAINS_DIR="$PROJECT_ROOT/chains"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

show_help() {
    cat << EOF
Chain Manager for cosmos-docker

USAGE:
    ./scripts/chain-manager.sh [COMMAND] [OPTIONS]

COMMANDS:
    list                    List all available chains
    use <chain-id>          Set active chain (copies to .env)
    pull <chain-name>       Pull chain config from cosmos chain registry
    create <chain-id>       Create custom chain config from template
    validate <chain-id>     Validate chain configuration
    help                    Show this help message

EXAMPLES:
    ./scripts/chain-manager.sh list
    ./scripts/chain-manager.sh use kaiyo-1
    ./scripts/chain-manager.sh pull osmosis          # From chain registry
    ./scripts/chain-manager.sh create my-devnet      # Custom template
    ./scripts/chain-manager.sh validate phoenix-1

CHAIN ORGANIZATION:
    chains/mainnet/         Production chain configurations
    chains/testnet/         Testnet chain configurations

CHAIN REGISTRY INTEGRATION:
    The 'pull' command automatically pulls configuration from the
    cosmos/chain-registry for 200+ supported chains. For custom chains
    or devnets, use 'create <name>'.
    
EOF
}

list_chains() {
    log "Available chains:"
    echo
    
    if [ -d "$CHAINS_DIR/mainnet" ]; then
        echo -e "${BLUE}MAINNET CHAINS:${NC}"
        for env_file in "$CHAINS_DIR/mainnet"/*.env; do
            if [ -f "$env_file" ]; then
                chain_id=$(basename "$env_file" .env)
                # Extract network name from file if available
                network=$(grep "^NETWORK=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
                if [ -n "$network" ]; then
                    echo "  $chain_id ($network)"
                else
                    echo "  $chain_id"
                fi
            fi
        done
        echo
    fi
    
    if [ -d "$CHAINS_DIR/testnet" ]; then
        echo -e "${BLUE}TESTNET CHAINS:${NC}"
        for env_file in "$CHAINS_DIR/testnet"/*.env; do
            if [ -f "$env_file" ]; then
                chain_id=$(basename "$env_file" .env)
                network=$(grep "^NETWORK=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
                if [ -n "$network" ]; then
                    echo "  $chain_id ($network)"
                else
                    echo "  $chain_id"
                fi
            fi
        done
    fi
}

use_chain() {
    local chain_id="$1"
    if [ -z "$chain_id" ]; then
        error "Chain ID required. Usage: use <chain-id>"
    fi
    
    # Look for chain in mainnet first, then testnet
    local env_file=""
    if [ -f "$CHAINS_DIR/mainnet/$chain_id.env" ]; then
        env_file="$CHAINS_DIR/mainnet/$chain_id.env"
    elif [ -f "$CHAINS_DIR/testnet/$chain_id.env" ]; then
        env_file="$CHAINS_DIR/testnet/$chain_id.env"
    else
        error "Chain '$chain_id' not found. Run 'list' to see available chains."
    fi
    
    log "Setting active chain to: $chain_id"
    cp "$env_file" "$PROJECT_ROOT/.env"
    log "Copied $env_file to .env"
    
    # Show current chain info
    local network=$(grep "^NETWORK=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2 || echo "")
    local daemon=$(grep "^DAEMON_NAME=" "$PROJECT_ROOT/.env" 2>/dev/null | cut -d'=' -f2 || echo "")
    echo
    echo -e "${GREEN}Active Chain:${NC} $chain_id"
    [ -n "$network" ] && echo -e "${GREEN}Network:${NC} $network"
    [ -n "$daemon" ] && echo -e "${GREEN}Daemon:${NC} $daemon"
}

pull_chain() {
    local chain_name="$1"
    if [ -z "$chain_name" ]; then
        error "Chain name required. Usage: pull <chain-name>"
    fi
    
    # Ask if mainnet or testnet
    echo "Is this a mainnet or testnet chain?"
    echo "1) mainnet"
    echo "2) testnet"
    read -p "Choice [1]: " choice
    choice=${choice:-1}
    
    local chain_type=""
    case $choice in
        1) chain_type="mainnet" ;;
        2) chain_type="testnet" ;;
        *) error "Invalid choice" ;;
    esac
    
    local target_file="$CHAINS_DIR/$chain_type/$chain_name.env"
    
    if [ -f "$target_file" ]; then
        error "Chain configuration already exists: $target_file"
    fi
    
    log "Pulling new $chain_type chain configuration: $chain_name"
    
    # Pull from chain registry
    create_from_registry "$chain_name" "$chain_type"
}

create_from_registry() {
    local chain_name="$1"
    local chain_type="$2"
    
    local target_file="$CHAINS_DIR/$chain_type/$chain_name.env"
    
    log "Pulling chain configuration from registry: $chain_name"
    
    # Try mainnet first, then testnet
    local chain_json_url=""
    local raw_base="https://raw.githubusercontent.com/cosmos/chain-registry/master"
    
    if [ "$chain_type" = "mainnet" ]; then
        chain_json_url="$raw_base/$chain_name/chain.json"
    else
        chain_json_url="$raw_base/testnets/$chain_name/chain.json"
    fi
    
    # Download chain.json
    if ! curl -sf "$chain_json_url" > /tmp/chain.json; then
        error "Chain $chain_name not found in chain-registry for $chain_type"
    fi
    
    # Extract fields using jq
    local chain_id=$(jq -r .chain_id /tmp/chain.json)
    local daemon_name=$(jq -r .daemon_name /tmp/chain.json)
    local daemon_home=$(jq -r .node_home /tmp/chain.json)
    local repo=$(jq -r '.codebase.git_repo // .codebase.repository' /tmp/chain.json)
    local raw_version=$(jq -r .codebase.recommended_version /tmp/chain.json)
    # Clean up version tag - remove duplicate 'v' prefixes and ensure single 'v' prefix
    local version=$(echo "$raw_version" | sed 's/^v*//; s/^/v/')
    local genesis_url=$(jq -r '.codebase.genesis.genesis_url // .genesis.genesis_url' /tmp/chain.json)
    local seeds=$(jq -r '.peers.seeds | map("\(.id)@\(.address)") | join(",")' /tmp/chain.json)
    local persistent_peers=$(jq -r '.peers.persistent_peers | map("\(.id)@\(.address)") | join(",")' /tmp/chain.json)
    
    # Prefer fixed_min_gas_price, then low_gas_price, then empty
    local min_gas_price=$(jq -r '
      (.fees.fee_tokens[] | select(.fixed_min_gas_price != null) | "\(.fixed_min_gas_price)\(.denom)") //
      (.fees.fee_tokens[] | select(.low_gas_price != null) | "\(.low_gas_price)\(.denom)") //
      ""
    ' /tmp/chain.json | head -n1)
    
    # Try to get snapshot URL from Polkachu API
    local snapshot_chain=""
    if [ "$chain_type" = "testnet" ]; then
        snapshot_chain="$chain_name/testnet"
    else
        snapshot_chain="$chain_name/mainnet"
    fi
    
    local snapshot_url=""
    if [ -n "$snapshot_chain" ]; then
        log "Checking for snapshot from Polkachu API for $snapshot_chain..."
        snapshot_url=$(curl -s -H "x-polkachu: cosmos-docker" "https://polkachu.com/api/v2/chain_snapshots/$snapshot_chain" 2>/dev/null | jq -r '.snapshot.url // empty' 2>/dev/null || echo "")
        if [ -n "$snapshot_url" ] && [ "$snapshot_url" != "null" ]; then
            log "Found snapshot: $snapshot_url"
        else
            log "No snapshot found from Polkachu API"
            snapshot_url=""
        fi
    fi
    
    # Write chain-specific .env file
    cat > "$target_file" <<EOF
# $chain_id ($chain_name) Specific Configuration
# Chain-specific overrides for $chain_id
# Common settings are inherited from defaults.env

# === CHAIN-SPECIFIC CONFIGURATION ===

# Core Configuration
NETWORK=$chain_id
MONIKER=${chain_name}-node
USER=ubuntu
DAEMON_NAME=$daemon_name
DAEMON_HOME=$daemon_home

# Node Version and Build
NODE_VERSION=$version
NODE_REPO=$repo

# Network Configuration
GENESIS_URL=$genesis_url
SEEDS=$seeds
PERSISTENT_PEERS=$persistent_peers

# Snapshot Configuration
SNAPSHOT=auto
SNAPSHOT_CHAIN=$snapshot_chain

# Public API Configuration
PUBLIC_API_URL=

# Logging
LOG_LEVEL=info
NODE_LOG_FORMAT=plain

# External address (set to auto for automatic detection or specify manually)
EXTERNAL_ADDRESS=auto

# Sync Configuration (Kujira-specific)
FASTSYNC_VERSION=v0

# Pruning configuration
PRUNING_STRATEGY=custom
PRUNING_KEEP_RECENT=362880
PRUNING_INTERVAL=100

# Optional: Additional daemon flags
EXTRA_FLAGS=
EOF
    
    # Only add minimum gas price if it exists and is not empty
    if [ -n "$min_gas_price" ] && [ "$min_gas_price" != "null" ] && [ "$min_gas_price" != "" ]; then
        cat >> "$target_file" <<EOF

# Gas Price Override
MIN_GAS_PRICE=$min_gas_price
EOF
    fi
    
    # Clean up
    rm -f /tmp/chain.json
    
    log "Pulled chain configuration from registry: $target_file"
}

create_chain() {
    local chain_id="$1"
    if [ -z "$chain_id" ]; then
        error "Chain ID required. Usage: create <chain-id>"
    fi
    
    # Create custom chain config from template
    local target_file="$CHAINS_DIR/mainnet/$chain_id.env"
    
    if [ -f "$target_file" ]; then
        error "Chain configuration already exists: $target_file"
    fi
    
    log "Creating new custom chain configuration: $chain_id"
    
    # Create from template
    cat > "$target_file" << EOF
# Chain-specific overrides for $chain_id
# Common settings are inherited from defaults.env

# === CHAIN-SPECIFIC CONFIGURATION ===

# Core Configuration
NETWORK=$chain_id
MONIKER=${chain_id}-node
USER=ubuntu
DAEMON_NAME=
DAEMON_HOME=

# Node Version and Build
NODE_VERSION=
NODE_REPO=

# Network Configuration
GENESIS_URL=
SEEDS=
PERSISTENT_PEERS=

# Snapshot Configuration
SNAPSHOT=auto
SNAPSHOT_CHAIN=

# Public API Configuration
PUBLIC_API_URL=

# Gas Price Override
MIN_GAS_PRICE=

# Logging
LOG_LEVEL=info

# External address (set to auto for automatic detection or specify manually)
EXTERNAL_ADDRESS=auto

# Sync Configuration
FASTSYNC_VERSION=v0

# Pruning configuration
PRUNING_STRATEGY=custom
PRUNING_KEEP_RECENT=362880
PRUNING_INTERVAL=100

# Optional: Additional daemon flags
EXTRA_FLAGS=
EOF
    
    log "Created template: $target_file"
    warn "Please edit the configuration file to add chain-specific settings"
}

validate_chain() {
    local chain_id="$1"
    if [ -z "$chain_id" ]; then
        error "Chain ID required. Usage: validate <chain-id>"
    fi
    
    # Find the env file
    local env_file=""
    if [ -f "$CHAINS_DIR/mainnet/$chain_id.env" ]; then
        env_file="$CHAINS_DIR/mainnet/$chain_id.env"
    elif [ -f "$CHAINS_DIR/testnet/$chain_id.env" ]; then
        env_file="$CHAINS_DIR/testnet/$chain_id.env"
    else
        error "Chain '$chain_id' not found"
    fi
    
    log "Validating chain configuration: $chain_id"
    
    # Check required fields
    local required_fields=("NETWORK" "DAEMON_NAME" "NODE_VERSION" "NODE_REPO")
    local missing_fields=()
    
    for field in "${required_fields[@]}"; do
        local value=$(grep "^$field=" "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "")
        if [ -z "$value" ]; then
            missing_fields+=("$field")
        fi
    done
    
    if [ ${#missing_fields[@]} -gt 0 ]; then
        error "Missing required fields: ${missing_fields[*]}"
    fi
    
    log "Chain configuration is valid"
}

# Main command processing
case "${1:-help}" in
    list|ls)
        list_chains
        ;;
    use|switch)
        use_chain "$2"
        ;;
    pull)
        pull_chain "$2"
        ;;
    create)
        create_chain "$2"
        ;;
    validate|check)
        validate_chain "$2"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        error "Unknown command: $1. Use 'help' for usage information."
        ;;
esac
