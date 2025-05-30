# Generic Cosmos Chain Docker

[![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/)
[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-2496ED?style=flat-square&logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Cosmos](https://img.shields.io/badge/Cosmos-2E3148?style=flat-square&logo=cosmos&logoColor=white)](https://cosmos.network/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)

Run any Cosmos chain fullnode in Docker Compose.

This Docker Compose setup provides a generic environment for running any Cosmos-based blockchain fullnode. Simply copy a chain-specific environment file and start your node!

## Supported Chains

This setup works with any Cosmos-based blockchain. Included example configurations:

- **thorchain-1** - THORChain mainnet
- **cosmoshub-4** - Cosmos Hub mainnet  
- **osmosis-1** - Osmosis mainnet
- **noble-1** - Noble mainnet
- **theta-testnet-001** - Cosmos Hub testnet

You can easily create configuration files for other chains by copying and modifying the provided examples.

## System Requirements

- **CPU**: 4+ cores (8+ cores recommended for validator nodes)
- **RAM**: 16GB minimum (32GB+ recommended, varies by chain)
- **Storage**: 500GB+ SSD (varies significantly by chain)
- **Network**: Stable internet connection with good bandwidth
- **Docker**: Docker Engine 20.10+ and Docker Compose v2
- **OS**: Linux (Ubuntu 20.04+ recommended), macOS, or Windows with WSL2

## Prerequisites

1. Install Docker and Docker Compose:
```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Log out and back in for group changes to take effect
```

2. Verify installation:
```bash
docker --version
docker compose version
```

## Validation

Before deploying, you can validate your setup using the included validation script:

```bash
./validate.sh
```

This script will:
- ✅ Check dependencies (Docker, Docker Compose, Make)
- ✅ Validate YAML syntax and Docker Compose configuration
- ✅ Test environment file formats
- ✅ Verify Makefile targets
- ✅ Check file structure and permissions
- ✅ Test Docker image availability
- ✅ Run basic security checks

## Quick Start

### 1. Clone and Setup
```bash
# Clone the repository
git clone https://github.com/your-org/cosmos-docker.git
cd cosmos-docker
```

### 2. Choose Your Chain
Pick one of the pre-configured chains or create your own:

```bash
# For THORChain mainnet
cp thorchain-1.env .env

# For Cosmos Hub mainnet  
cp cosmoshub-4.env .env

# For Osmosis mainnet
cp osmosis-1.env .env

# For Noble mainnet
cp noble-1.env .env

# For Cosmos Hub testnet
cp theta-testnet-001.env .env
```

### 3. Start Your Node
```bash
make start
```

That's it! Your node will start syncing automatically.

### Manual Configuration

If you prefer to configure manually:

```bash
# Copy an example configuration
cp thorchain-1.env .env

# Edit configuration as needed
nano .env

# Start the node
docker compose up -d

# Monitor logs
docker compose logs -f cosmos
```

## Development Mode

For development and testing, use the enhanced development configuration:

```bash
# Start with development overrides (debug logging, faster health checks)
docker compose -f cosmos.yml -f docker-compose.dev.yml up -d

# Start with development tools (includes utilities like curl, jq, htop)
docker compose -f cosmos.yml -f docker-compose.dev.yml --profile dev-tools up -d

# Start with full monitoring stack (Prometheus + Grafana)
docker compose -f cosmos.yml -f docker-compose.dev.yml --profile monitoring up -d

# Access development tools
docker compose exec dev-tools bash

# Access Grafana dashboard
open http://localhost:3000  # admin/admin
```

See `dev-config/README.md` for detailed development environment documentation.

## Available Make Commands

### Production Commands
- `make start` - Start cosmos node with monitoring
- `make stop` - Stop cosmos node  
- `make restart` - Restart cosmos node
- `make logs` - Show cosmos service logs
- `make status` - Show comprehensive node status
- `make monitor` - Run monitoring script
- `make clean` - Remove all containers, volumes, and data
- `make help` - Show all available commands

### Development Commands
- `make dev` - Start with development configuration (debug logging, faster health checks)
- `make dev-tools` - Start with development tools (curl, jq, htop, etc.)
- `make dev-monitor` - Start with monitoring stack (Prometheus + Grafana)
- `make dev-all` - Start with all development features
- `make dev-stop` - Stop development environment
- `make dev-logs` - Show development logs

## Configuration

### Environment Files

This project provides pre-configured environment files for popular Cosmos chains:

1. **`thorchain-1.env`** - THORChain mainnet configuration
2. **`cosmoshub-4.env`** - Cosmos Hub mainnet configuration  
3. **`osmosis-1.env`** - Osmosis mainnet configuration
4. **`noble-1.env`** - Noble mainnet configuration
5. **`theta-testnet-001.env`** - Cosmos Hub testnet configuration

### Main Configuration Options

The key settings you'll likely want to customize:

- `NODE_VERSION`: Node version to run (e.g., v18.1.0)
- `NODE_REPO`: Git repository URL for the node source code
- `DAEMON_NAME`: Name of the daemon binary (e.g., gaiad, osmosisd, thornode)
- `MONIKER`: Your node's moniker/name
- `NETWORK`: Chain ID (e.g., cosmoshub-4, osmosis-1)
- `GENESIS_URL`: URL to download the genesis file
- `SEEDS`: Comma-separated list of seed nodes for peer discovery
- `SNAPSHOT`: Optional snapshot URL for faster sync
- `SNAPSHOT_API_URL`: API endpoint to find latest snapshots
- `SNAPSHOT_BASE_URL`: Base URL for downloading snapshots
- `EXTRA_FLAGS`: Additional flags to pass to the daemon binary
- `LOG_LEVEL`: Logging level (info, warn, error, trace)

### Creating Custom Chain Configurations

To add support for a new Cosmos chain:

1. **Copy an existing configuration:**
```bash
cp cosmoshub-4.env mynewchain-1.env
```

2. **Update the key variables:**
```bash
# Edit the new file
nano mynewchain-1.env

# Update these required fields:
NETWORK=mynewchain-1
DAEMON_NAME=newchaind
NODE_VERSION=v1.0.0
NODE_REPO=https://github.com/mynewchain/mynewchain
GENESIS_URL=https://raw.githubusercontent.com/mynewchain/mainnet/genesis.json
SEEDS=your,seed,nodes,here
```

3. **Use your new configuration:**
```bash
cp mynewchain-1.env .env
make start
```

## Ports

The following ports are exposed by default (configurable in .env):

- `26657`: RPC port (Tendermint RPC)
- `26656`: P2P port (for peer connections)
- `9090`: gRPC port
- `9091`: gRPC-Web port
- `1317`: REST API port
- `26660`: Prometheus metrics port

**Note**: THORChain uses custom ports (27147/27146) which are pre-configured in `thorchain-1.env`.

## Data Persistence

### Storage Options

Cosmos blockchain data size varies significantly by chain:
- **Cosmos Hub**: ~500GB+
- **Osmosis**: ~1TB+  
- **THORChain**: ~1TB+
- **Noble**: ~100GB+

You have two storage options:

#### Option 1: Docker Volume (Default)
Node data is stored in Docker volumes:
- `cosmos-data`: Blockchain data and configuration  
- `cosmos-builds`: Built binaries

This is the default and simplest option. Docker manages the storage location.

#### Option 2: Custom Path (Recommended for Production)
For production deployments or when using a dedicated disk, the default path pattern is `/mnt/data/blockchain/{CHAIN-ID}`:

1. **Prepare your storage location:**
```bash
# Example: Mount a separate disk to /mnt/data
sudo mkdir -p /mnt/data/blockchain
sudo chown 10001:10001 /mnt/data/blockchain
```

2. **The DATA_DIR is automatically set to:**
```bash
DATA_DIR=/mnt/data/blockchain/${NETWORK}
```

3. **For custom paths, modify DATA_DIR in your .env file:**
```bash
# Custom path example
DATA_DIR=/my/custom/path/cosmoshub-4
```

#### Typical Production Setup
```bash
# 1. Attach and mount a dedicated SSD
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
echo '/dev/sdb /mnt/data ext4 defaults 0 2' | sudo tee -a /etc/fstab

# 2. Prepare cosmos directory (will be created per chain automatically)
sudo mkdir -p /mnt/data/blockchain
sudo chown 10001:10001 /mnt/data/blockchain

# 3. Copy chain configuration (DATA_DIR already configured correctly)
cp cosmoshub-4.env .env

# 4. Start the node
make start
```

## Monitoring

Check node status:
```bash
# Service status
docker compose ps

# Node sync status (adjust port for your chain)
curl http://localhost:26657/status  # Standard Cosmos
curl http://localhost:27147/status  # THORChain

# View logs
docker compose logs cosmos
make logs
```

## Updates

To update to a new version:

1. Update `NODE_VERSION` in `.env`
2. Rebuild and restart:
```bash
docker compose down
docker compose up --build -d
```

## Troubleshooting

### Common Issues

**Node fails to start or crashes:**
```bash
# Check logs for errors
make logs

# Check system resources
docker stats

# Verify Docker has enough resources allocated
```

**Sync is very slow:**
- Ensure you have a fast SSD
- Check your internet connection speed
- Consider using a more recent snapshot

**Port conflicts:**
- Check if ports are already in use: `sudo netstat -tulpn | grep :26657`
- Modify port configuration in `.env` file

**Out of disk space:**
```bash
# Check disk usage
df -h

# Clean up Docker resources
make clean
docker system prune -af
```

**Permission errors:**
```bash
# Fix Docker permissions
sudo usermod -aG docker $USER
# Log out and back in

# Fix data directory permissions (if using custom DATA_DIR)
sudo chown -R 10001:10001 /your/data/path
```

**Storage issues:**
```bash
# Check available space
df -h

# For custom data directory (per chain)
du -sh /mnt/data/blockchain/cosmoshub-4

# For Docker volumes
docker system df
```

### Getting Help

- Check logs: `make logs`
- Node status: `make status`
- Monitor health: `make monitor`
- Cosmos Documentation: https://docs.cosmos.network/
- Chain-specific documentation:
  - THORChain: https://docs.thorchain.org/
  - Osmosis: https://docs.osmosis.zone/
  - Noble: https://docs.nobleassets.xyz/

## Chain-Specific Notes

### THORChain
- Uses custom ports (27147/27146)
- Requires specific snapshot format
- High storage requirements (~1TB+)

### Osmosis  
- Very high storage requirements (~1TB+)
- Active development with frequent updates
- Rich ecosystem of tools

### Cosmos Hub
- Most stable and well-documented
- Moderate storage requirements (~500GB)
- Good for beginners

### Noble
- Lightweight chain focused on asset issuance
- Lower storage requirements (~100GB)
- Fast sync times

## Support

For chain-specific issues, consult the respective documentation linked above. For issues with this Docker setup, please open an issue in this repository.
