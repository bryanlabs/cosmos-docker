#!/bin/bash
# State Sync Parameter Discovery Script
# Automatically finds optimal block height and app hash for state sync
# Handles multiple RPC servers with varying history depths

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
TIMEOUT=10
MIN_BLOCKS_BEHIND=1000
MAX_BLOCKS_BEHIND=5000
PREFERRED_BLOCKS_BEHIND=3000

# Chain configurations
declare -A CHAIN_CONFIGS=(
    ["osmosis"]="osmosis-1.env osmosis-rpc.polkachu.com:443,osmosis-rpc.bryanlabs.net:443"
    ["cosmos"]="cosmoshub-4.env cosmos-rpc.polkachu.com:443,cosmos-rpc.bryanlabs.net:443"
    ["noble"]="noble-1.env noble-rpc.polkachu.com:443,noble-rpc.bryanlabs.net:443"
)

log() {
    echo -e "${CYAN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Function to query RPC endpoint with timeout
query_rpc() {
    local url="$1"
    local endpoint="$2"
    local timeout="${3:-$TIMEOUT}"
    
    curl -s --max-time "$timeout" --fail "$url/$endpoint" 2>/dev/null
}

# Function to get current block height from RPC
get_current_height() {
    local rpc_url="$1"
    local response
    
    response=$(query_rpc "$rpc_url" "status")
    if [[ $? -eq 0 && -n "$response" ]]; then
        echo "$response" | jq -r '.result.sync_info.latest_block_height // empty' 2>/dev/null
    fi
}

# Function to get app hash for a specific height
get_app_hash() {
    local rpc_url="$1"
    local height="$2"
    local response
    
    response=$(query_rpc "$rpc_url" "block?height=$height")
    if [[ $? -eq 0 && -n "$response" ]]; then
        echo "$response" | jq -r '.result.block.header.app_hash // empty' 2>/dev/null
    fi
}

# Function to find the best available height for an RPC server
find_best_height() {
    local rpc_url="$1"
    local current_height="$2"
    local preferred_height="$3"
    
    log "Testing RPC server: $rpc_url"
    
    # Try preferred height first
    local app_hash
    app_hash=$(get_app_hash "$rpc_url" "$preferred_height")
    if [[ -n "$app_hash" && "$app_hash" != "null" ]]; then
        info "✓ Preferred height $preferred_height available with hash: $app_hash"
        echo "$preferred_height:$app_hash"
        return 0
    fi
    
    # Binary search to find the oldest available block
    local min_height=$((current_height - MAX_BLOCKS_BEHIND))
    local max_height=$((current_height - MIN_BLOCKS_BEHIND))
    local best_height=""
    local best_hash=""
    
    info "Preferred height not available, searching between $min_height and $max_height"
    
    # Start from more recent blocks and work backwards
    for offset in $(seq $MIN_BLOCKS_BEHIND 500 $MAX_BLOCKS_BEHIND); do
        local test_height=$((current_height - offset))
        if [[ $test_height -lt 1 ]]; then
            break
        fi
        
        app_hash=$(get_app_hash "$rpc_url" "$test_height")
        if [[ -n "$app_hash" && "$app_hash" != "null" ]]; then
            best_height="$test_height"
            best_hash="$app_hash"
            info "✓ Found available height: $best_height (${offset} blocks behind)"
            break
        fi
    done
    
    if [[ -n "$best_height" ]]; then
        echo "$best_height:$best_hash"
        return 0
    else
        warn "✗ No suitable height found for $rpc_url"
        return 1
    fi
}

# Function to find earliest available block on server
find_earliest_block() {
    local rpc_url="$1"
    local current_height="$2"
    local target_height="$3"
    
    log_info "Checking block availability on $rpc_url (target: $target_height)"
    
    # Binary search to find earliest available block
    local low=$((current_height - 50000))  # Start checking from 50k blocks back
    local high=$current_height
    local earliest=$current_height
    
    # Ensure low is at least 1
    if [ "$low" -lt 1 ]; then
        low=1
    fi
    
    # Quick check: try the target height first
    if get_block_hash "$rpc_url" "$target_height" >/dev/null 2>&1; then
        echo "$target_height"
        return 0
    fi
    
    # Binary search for earliest available block
    while [ $low -le $high ]; do
        local mid=$(( (low + high) / 2 ))
        
        if get_block_hash "$rpc_url" "$mid" >/dev/null 2>&1; then
            earliest=$mid
            high=$((mid - 1))
        else
            low=$((mid + 1))
        fi
    done
    
    # Use earliest found block, but ensure safety margin
    local safe_height=$((earliest + MIN_SAFETY_MARGIN))
    if [ "$safe_height" -gt "$current_height" ]; then
        safe_height=$((current_height - MIN_SAFETY_MARGIN))
    fi
    
    echo "$safe_height"
}

# Function to process a single chain
process_chain() {
    local chain_name="$1"
    local rpc_servers="$2"
    
    echo
    log_info "=== Processing $chain_name chain ==="
    
    # Convert comma-separated RPC servers to array
    IFS=',' read -ra rpc_array <<< "$rpc_servers"
    
    local best_height=0
    local best_hash=""
    local best_server=""
    
    # Get current heights from all servers
    declare -A server_heights
    local max_height=0
    
    for rpc_url in "${rpc_array[@]}"; do
        # Remove any whitespace
        rpc_url=$(echo "$rpc_url" | tr -d ' ')
        
        if current_height=$(get_current_height "$rpc_url"); then
            server_heights["$rpc_url"]="$current_height"
            log_success "Current height from $rpc_url: $current_height"
            
            if [ "$current_height" -gt "$max_height" ]; then
                max_height="$current_height"
            fi
        else
            log_error "Cannot reach $rpc_url"
            server_heights["$rpc_url"]="0"
        fi
    done
    
    if [ "$max_height" -eq 0 ]; then
        log_error "No servers responded for $chain_name"
        return 1
    fi
    
    # Calculate target height (max_height - safety margin)
    local target_height=$((max_height - BLOCK_SAFETY_MARGIN))
    if [ "$target_height" -lt 1 ]; then
        target_height=1
    fi
    
    log_info "Target height for $chain_name: $target_height (max: $max_height, safety margin: $BLOCK_SAFETY_MARGIN)"
    
    # Try to get block hash from each server
    for rpc_url in "${rpc_array[@]}"; do
        rpc_url=$(echo "$rpc_url" | tr -d ' ')
        
        if [ "${server_heights[$rpc_url]}" -eq 0 ]; then
            continue  # Skip unreachable servers
        fi
        
        local actual_height="$target_height"
        
        # If target height is not available, find the best available height
        if ! get_block_hash "$rpc_url" "$target_height" >/dev/null 2>&1; then
            log_warning "$rpc_url doesn't have block $target_height, finding earliest available..."
            actual_height=$(find_earliest_block "$rpc_url" "${server_heights[$rpc_url]}" "$target_height")
        fi
        
        # Get the hash for the actual height
        if hash=$(get_block_hash "$rpc_url" "$actual_height"); then
            log_success "Got hash from $rpc_url at height $actual_height: $hash"
            
            # Prefer the highest height that's still safe
            if [ "$actual_height" -gt "$best_height" ]; then
                best_height="$actual_height"
                best_hash="$hash"
                best_server="$rpc_url"
            fi
        else
            log_warning "Failed to get hash from $rpc_url at height $actual_height"
        fi
    done
    
    # Output results
    if [ "$best_height" -gt 0 ] && [ -n "$best_hash" ]; then
        echo
        log_success "=== Best parameters for $chain_name ==="
        echo "STATESYNC_TRUST_HEIGHT=$best_height"
        echo "STATESYNC_TRUST_HASH=$best_hash"
        echo "# Source: $best_server"
        echo "# Max height was: $max_height"
        echo "# Safety margin: $((max_height - best_height)) blocks"
        
        # Verify hash with other servers
        echo
        log_info "Verifying hash with other servers..."
        for rpc_url in "${rpc_array[@]}"; do
            rpc_url=$(echo "$rpc_url" | tr -d ' ')
            if [ "$rpc_url" != "$best_server" ] && [ "${server_heights[$rpc_url]}" -gt 0 ]; then
                if verify_hash=$(get_block_hash "$rpc_url" "$best_height" 2>/dev/null); then
                    if [ "$verify_hash" = "$best_hash" ]; then
                        log_success "✓ Hash verified on $rpc_url"
                    else
                        log_warning "✗ Hash mismatch on $rpc_url: $verify_hash"
                    fi
                else
                    log_warning "✗ Cannot verify on $rpc_url (block not available)"
                fi
            fi
        done
        
        return 0
    else
        log_error "Could not find suitable state sync parameters for $chain_name"
        return 1
    fi
}

# Main function
main() {
    echo "State Sync Parameter Discovery Script"
    echo "====================================="
    
    # Check required tools
    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is required but not installed"
        exit 1
    fi
    
    # Process command line arguments
    local specific_chain=""
    local update_configs=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --chain)
                specific_chain="$2"
                shift 2
                ;;
            --update)
                update_configs=true
                shift
                ;;
            --safety-margin)
                BLOCK_SAFETY_MARGIN="$2"
                shift 2
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo "Options:"
                echo "  --chain CHAIN        Process only specific chain (osmosis, noble, cosmos)"
                echo "  --update            Update .env files with discovered parameters"
                echo "  --safety-margin N   Set safety margin in blocks (default: $BLOCK_SAFETY_MARGIN)"
                echo "  --help              Show this help message"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Process chains
    local exit_code=0
    
    if [ -n "$specific_chain" ]; then
        if [ -n "${CHAINS[$specific_chain]:-}" ]; then
            if ! process_chain "$specific_chain" "${CHAINS[$specific_chain]}"; then
                exit_code=1
            fi
        else
            log_error "Unknown chain: $specific_chain"
            log_info "Available chains: ${!CHAINS[*]}"
            exit 1
        fi
    else
        for chain in "${!CHAINS[@]}"; do
            if ! process_chain "$chain" "${CHAINS[$chain]}"; then
                exit_code=1
            fi
        done
    fi
    
    echo
    if [ $exit_code -eq 0 ]; then
        log_success "All chains processed successfully!"
        
        if [ "$update_configs" = true ]; then
            log_info "Note: --update flag specified but auto-update not implemented yet"
            log_info "Please manually update the .env files with the parameters above"
        fi
    else
        log_warning "Some chains failed to process. Check logs above."
    fi
    
    exit $exit_code
}

# Run main function with all arguments
main "$@"
