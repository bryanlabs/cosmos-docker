# Cosmos Docker Repository Overview

## What This Repository Does

This is a **Generic Cosmos Chain Docker** setup that provides a unified environment for running any Cosmos-based blockchain fullnode using Docker Compose. It's designed to be chain-agnostic and easily configurable for different Cosmos networks.

### Key Features
- **Universal Cosmos Support**: Works with any Cosmos-based blockchain
- **Pre-configured Chains**: Includes ready-to-use configurations for popular chains
- **Docker-based**: Containerized deployment for consistency and isolation
- **Monitoring Ready**: Built-in monitoring and logging capabilities
- **Development Mode**: Enhanced development environment with debugging tools
- **State Sync Support**: Fast synchronization using state sync or snapshots

## Supported Chains (Pre-configured)

The repository includes environment files for these popular chains:

- **thorchain-1** - THORChain mainnet (custom ports: RPC 27147, P2P 27146)
- **cosmoshub-4** - Cosmos Hub mainnet 
- **osmosis-1** - Osmosis mainnet
- **noble-1** - Noble mainnet
- **phoenix-1** - Terra mainnet
- **kaiyo-1** - Kujira mainnet
- **columbus-5** - Terra Classic

## Quick Deployment Guide

### Basic Deployment Process
```bash
# 1. Clone repository
git clone <repo-url>
cd cosmos-docker

# 2. Choose and copy chain configuration
cp thorchain-1.env .env        # For THORChain
cp cosmoshub-4.env .env        # For Cosmos Hub
cp osmosis-1.env .env          # For Osmosis
# ... or any other chain

# 3. Start the node
make start
```

### Alternative Manual Deployment
```bash
# Copy configuration
cp thorchain-1.env .env

# Start with docker-compose directly
docker compose up -d

# Monitor logs
docker compose logs -f cosmos
```

## Configuration Architecture

### Environment File Structure
The system uses a **layered configuration approach**:

1. **`defaults.env`** - Common defaults for all Cosmos chains
2. **`{chain}.env`** - Chain-specific overrides (e.g., `thorchain-1.env`)
3. **`.env`** - Active configuration (copied from a chain file)

### Key Configuration Variables

#### Core Settings
- `NETWORK` - Chain ID (e.g., thorchain-1, cosmoshub-4)
- `DAEMON_NAME` - Binary name (e.g., thornode, gaiad, osmosisd)
- `NODE_VERSION` - Version to build/run
- `NODE_REPO` - Git repository URL
- `MONIKER` - Your node's display name

#### Network Settings
- `SEEDS` - Seed nodes for peer discovery
- `PERSISTENT_PEERS` - Always-connected peers
- `GENESIS_URL` - Genesis file download URL
- `EXTERNAL_ADDRESS` - External IP (auto-detected if "auto")

#### Port Configuration
- `P2P_PORT` - P2P communication (default: 26656)
- `RPC_PORT` - RPC endpoint (default: 26657)
- `REST_PORT` - REST API (default: 1317)
- `GRPC_PORT` - gRPC endpoint (default: 9090)

#### Sync Options
- `SNAPSHOT` - Snapshot URL for fast sync
- `SNAPSHOT_API_URL` - API to find latest snapshots
- `STATESYNC_ENABLE` - Enable state sync (true/false)

## Available Make Commands

### Production Commands
- `make start` - Start node with monitoring
- `make stop` - Stop the node
- `make restart` - Restart the node
- `make logs` - View node logs
- `make status` - Show comprehensive node status
- `make monitor` - Run monitoring script
- `make build` - Force rebuild Docker images (required after code changes)
- `make clean` - Remove containers, volumes, and data
- `make help` - Show all commands

### Development Commands
- `make dev` - Start with debug logging and faster health checks
- `make dev-tools` - Start with development utilities (curl, jq, htop)
- `make dev-monitor` - Start with Prometheus + Grafana monitoring
- `make dev-all` - Start with all development features
- `make dev-stop` - Stop development environment

### Development Access
```bash
# Access development tools container
docker compose exec dev-tools bash

# Access Grafana dashboard
open http://localhost:3000  # admin/admin
```

## Important: Rebuilding After Changes

**CRITICAL**: If you modify any of the following files, you MUST rebuild the Docker images before starting:

- `builder/docker-entrypoint.sh` - Builder script changes
- `builder/Dockerfile` - Builder image changes  
- `cosmos/Dockerfile.source` - Node image changes
- Any files in the `builder/` or `cosmos/` directories

### When to Rebuild
```bash
# After modifying builder scripts or Dockerfiles
make build

# Then start normally
make start
```

### Why Rebuilding is Required
Docker images are built once and cached. When you modify:
- **Builder scripts** (`builder/docker-entrypoint.sh`) - Changes to build logic, WasmVM handling, etc.
- **Dockerfiles** - Changes to base images, dependencies, or build steps
- **Build context files** - Any files copied into the Docker images

The running containers will continue using the old cached image until you explicitly rebuild with `make build`.

### Quick Rebuild Workflow
```bash
# Stop current containers
make stop

# Rebuild images with your changes
make build

# Start with new images
make start
```

## Docker Services Architecture

The setup uses multiple Docker services:

1. **`builder`** - Builds the node binary from source
2. **`cosmos`** - Main node service running the blockchain
3. **`dev-tools`** - Development utilities (when using dev profile)
4. **`prometheus`** - Metrics collection (when using monitoring profile)
5. **`grafana`** - Monitoring dashboard (when using monitoring profile)

## Data Storage

### Default Storage
- Uses Docker volumes for blockchain data
- Data persists between container restarts
- Located in Docker's volume directory

### Custom Data Directory
```bash
# In your .env file, set:
DATA_DIR=/custom/path/${NETWORK}
# The ${NETWORK} variable will be replaced with your chain ID
```

## Validation and Testing

### Pre-deployment Validation
```bash
./validate.sh
```

This checks:
- Docker and dependencies
- YAML syntax
- Environment file format
- Makefile targets
- File permissions
- Docker image availability
- Security settings

### Monitoring Node Status
```bash
# Quick status check
make status

# Continuous monitoring
make monitor

# View logs
make logs
```

## Creating Custom Chain Configurations

To add a new Cosmos chain:

1. **Copy existing configuration:**
```bash
cp cosmoshub-4.env mynewchain-1.env
```

2. **Edit the new file with chain-specific values:**
- `NETWORK` - New chain ID
- `DAEMON_NAME` - Chain's binary name
- `NODE_REPO` - Chain's GitHub/GitLab repo
- `NODE_VERSION` - Desired version
- `GENESIS_URL` - Genesis file URL
- `SEEDS` - Seed nodes
- Port configurations if non-standard

3. **Deploy:**
```bash
cp mynewchain-1.env .env
make start
```

## Common Troubleshooting

### Node Won't Start
1. Check `.env` file exists: `ls -la .env`
2. Validate configuration: `./validate.sh`
3. Check logs: `make logs`

### Sync Issues
1. Verify seeds/peers are accessible
2. Check if snapshot URL is valid
3. Consider using state sync instead

### Port Conflicts
1. Check if ports are already in use: `netstat -tulpn | grep <port>`
2. Modify port settings in `.env` file
3. Restart: `make restart`

### Storage Issues
1. Check disk space: `df -h`
2. Verify data directory permissions
3. Consider using custom `DATA_DIR`

## File Structure Reference

```
cosmos-docker/
├── .env                    # Active configuration (copy from chain file)
├── defaults.env           # Common defaults
├── {chain}.env           # Chain-specific configurations
├── cosmos.yml            # Main docker-compose file
├── docker-compose.dev.yml # Development overrides
├── Makefile              # Automation commands
├── validate.sh           # Validation script
├── monitor.sh            # Monitoring script
├── builder/              # Docker build context for node binary
├── cosmos/               # Docker context for node container
└── dev-config/           # Development configuration files
```

This architecture provides a flexible, maintainable way to run any Cosmos blockchain node with minimal configuration changes.
