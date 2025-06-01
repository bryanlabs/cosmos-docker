# Environment Configuration Structure

This directory uses a standardized environment configuration system that separates common Cosmos node settings from chain-specific configurations.

## File Structure

- **`defaults.env`** - Common defaults shared across all Cosmos chains
- **`thorchain-1.env`** - THORChain specific overrides
- **`cosmoshub-4.env`** - Cosmos Hub specific overrides  
- **`osmosis-1.env`** - Osmosis specific overrides
- **`noble-1.env`** - Noble specific overrides
- **`start-node.sh`** - Startup script that loads defaults + chain overrides

## How It Works

### 1. Common Defaults (`defaults.env`)
Contains all standard Cosmos node settings including:
- Default ports (P2P: 26656, RPC: 26657, REST: 1317, GRPC: 9090, etc.)
- P2P configuration (max peers, timeouts, etc.)
- RPC settings (CORS, connection limits, etc.)
- Consensus parameters (timeouts, block creation, etc.)
- Mempool configuration (size, cache, broadcast settings, etc.)
- Monitoring (Prometheus settings)
- Logging and debugging options
- Pruning defaults
- Database and storage settings

### 2. Chain-Specific Overrides
Each chain's `.env` file contains only the settings that differ from defaults:
- **Network identity** (NETWORK, MONIKER, DAEMON_NAME)
- **Version and repository** (NODE_VERSION, NODE_REPO)
- **Chain-specific ports** (if different from defaults)
- **Network endpoints** (seeds, peers, genesis URL, API URLs)
- **Snapshot configuration** (chain-specific snapshot sources)
- **State sync settings** (trust height/hash for the specific chain)
- **Gas prices** (chain-specific minimum gas prices)
- **Custom build flags** (EXTRA_FLAGS specific to the chain)

### 3. Standardized File Format
All chain-specific `.env` files follow this standardized order:

1. **Header** - Chain identification and purpose
2. **Chain-Specific Configuration Section** - All unique settings at the top
   - Core Configuration (NETWORK, MONIKER, DAEMON_NAME, etc.)
   - Node Version and Build information
   - Network Configuration (seeds, peers, genesis)
   - Port Configuration (if different from defaults)
   - Snapshot Configuration
   - State Sync Configuration
   - Public API Configuration
   - Gas Price Overrides
   - Any other chain-specific settings

This format ensures that:
- The most important and frequently changed values are at the top
- Chain-specific settings are easy to find and modify
- The file structure is consistent across all chains
- Common defaults are inherited automatically from `defaults.env`

### 3. Variable Resolution Order
When starting a node, variables are loaded in this order:
1. `defaults.env` is sourced first (provides base configuration)
2. Chain-specific `.env` file is sourced second (overrides defaults)
3. Variables from step 2 take precedence over step 1

## Usage

### Starting a Node
```bash
# Start THORChain node
./start-node.sh thorchain-1

# Start Cosmos Hub node  
./start-node.sh cosmoshub-4

# Start Osmosis node
./start-node.sh osmosis-1

# Start Noble node
./start-node.sh noble-1
```

### Manual Docker Compose
If you prefer manual control, you can still source the files manually:
```bash
# Source defaults first, then chain-specific overrides
source defaults.env
source thorchain-1.env

# Then start with docker-compose
docker-compose -f cosmos.yml up -d
```

### Checking Configuration
```bash
# See help and available chains
./start-node.sh --help

# Test configuration loading without starting
source defaults.env && source thorchain-1.env && env | grep -E "(NETWORK|DAEMON|PORT|RPC)" | sort
```

## Benefits

### 1. DRY (Don't Repeat Yourself)
- Common settings are defined once in `defaults.env`
- Chain files only contain what's actually different
- Reduces duplication and maintenance overhead
- All chain files follow the same standardized order with chain-specific overrides at the top

### 2. Consistency
- All chains share the same base configuration
- Easier to apply security updates or optimizations across all chains
- Standardized port layouts and settings
- Consistent variable ordering makes files easy to compare and understand

### 3. Clarity
- Chain files are much smaller and easier to understand
- Clear separation between common settings and chain-specific requirements
- New chains can be added by copying a template and changing minimal values
- Chain-specific values are clearly marked at the top of each file

### 4. Maintainability
- Updates to common settings only need to be made in one place
- Chain-specific customizations are isolated and obvious
- Easier to troubleshoot configuration issues
- Standardized format makes automated tooling easier to implement

## Customization

### Adding a New Chain
1. Copy an existing chain `.env` file (e.g., `cp cosmoshub-4.env mynewchain-1.env`)
2. Update the chain-specific values:
   - `NETWORK=mynewchain-1`
   - `DAEMON_NAME=mynewchaind`
   - `NODE_VERSION=v1.0.0`
   - `NODE_REPO=https://github.com/mynewchain/node`
   - Genesis URL, seeds, API endpoints
   - Minimum gas price
3. Test with `./start-node.sh mynewchain-1`

### Modifying Common Defaults
Edit `defaults.env` to change settings that should apply to all chains by default. Individual chains can still override these in their specific `.env` files if needed.

### Chain-Specific Customizations
Add any setting to a chain's `.env` file to override the default. For example, if a chain needs different P2P settings:
```bash
# In osmosis-1.env
MAX_INBOUND_PEERS=100  # Override default of 40
```

## Supported Variables

The startup script and docker-entrypoint.sh support these key variables:

### Core Configuration
- `NETWORK`, `MONIKER`, `USER`, `DAEMON_NAME`, `DAEMON_HOME`
- `NODE_VERSION`, `NODE_REPO`, `EXTRA_FLAGS`

### Network & Connectivity  
- `P2P_PORT`, `RPC_PORT`, `REST_PORT`, `GRPC_PORT`, `GRPC_WEB_PORT`
- `SEEDS`, `PERSISTENT_PEERS`, `EXTERNAL_ADDRESS`
- `MAX_INBOUND_PEERS`, `MAX_OUTBOUND_PEERS`

### Data & Snapshots
- `DATA_DIR`, `SNAPSHOT`, `SNAPSHOT_API_URL`, `SNAPSHOT_BASE_URL`
- `FORCE_REBUILD`

### State Sync
- `STATESYNC_ENABLE`, `STATESYNC_RPC_SERVERS`
- `STATESYNC_TRUST_HEIGHT`, `STATESYNC_TRUST_HASH`, `STATESYNC_TRUST_PERIOD`

### Performance & Behavior
- `MIN_GAS_PRICE`
- `PRUNING_STRATEGY`, `PRUNING_KEEP_RECENT`, `PRUNING_INTERVAL`
- `LOG_LEVEL`, `NODE_LOG_FORMAT`

## Migration from Old Format

If you have existing `.env` files with duplicate settings:

1. **Backup your current files**: `cp *.env *.env.backup`
2. **Identify unique settings**: Compare your chain files to find what's actually different
3. **Use new standardized files**: The standardized files in this repo contain the essential chain-specific settings
4. **Apply your customizations**: Add any custom settings you had to the appropriate chain file
5. **Test**: Use `./start-node.sh <chain>` to verify everything works

The new structure maintains all functionality while being much cleaner and easier to maintain.
