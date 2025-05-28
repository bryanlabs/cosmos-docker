# THORChain Docker

[![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://www.docker.com/)
[![Docker Compose](https://img.shields.io/badge/Docker%20Compose-2496ED?style=flat-square&logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![THORChain](https://img.shields.io/badge/THORChain-00CCAA?style=flat-square&logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj4KPHBhdGggZD0iTTEyIDJMMjIgMTJMMTIgMjJMMiAxMkwxMiAyWiIgZmlsbD0iI0ZGRkZGRiIvPgo8L3N2Zz4K&logoColor=white)](https://thorchain.org/)
[![YAML Lint](https://github.com/thorchain/thorchain-docker/actions/workflows/lint.yml/badge.svg)](https://github.com/thorchain/thorchain-docker/actions/workflows/lint.yml)
[![Docker Test](https://github.com/thorchain/thorchain-docker/actions/workflows/docker-test.yml/badge.svg)](https://github.com/thorchain/thorchain-docker/actions/workflows/docker-test.yml)
[![Security Scan](https://github.com/thorchain/thorchain-docker/actions/workflows/security.yml/badge.svg)](https://github.com/thorchain/thorchain-docker/actions/workflows/security.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)](http://makeapullrequest.com)

Run THORChain fullnode in Docker Compose.

This Docker Compose setup provides a complete THORChain fullnode environment based on the official THORNode Linux installation guide.

## System Requirements

- **CPU**: 4+ cores (8+ cores recommended for validator nodes)
- **RAM**: 16GB minimum (32GB+ recommended)
- **Storage**: 1TB+ SSD (grows over time)
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

### Option 1: Using Make (Recommended)
```bash
make start
```
This will automatically copy the environment file, start the services, and monitor the startup process.

### Option 2: Manual Setup

**For beginners (minimal configuration):**
```bash
cp .env.example .env
nano .env  # customize if needed
docker compose up -d
```

**For production (full configuration):**
```bash
cp thorchain-1.env .env
nano .env  # customize as needed
docker compose up -d
```

**Monitor logs:**
```bash
docker compose logs -f thorchain
```

## Available Make Commands

- `make start` - Start THORChain node with monitoring
- `make stop` - Stop THORChain node  
- `make restart` - Restart THORChain node
- `make logs` - Show thorchain service logs
- `make status` - Show comprehensive node status
- `make monitor` - Run monitoring script
- `make clean` - Remove all containers, volumes, and data
- `make help` - Show all available commands

## Configuration

### Configuration Files

This project provides two configuration templates:

1. **`.env.example`** - Minimal configuration with only essential settings
   - Perfect for beginners or simple setups
   - Contains basic options like node name, version, and data storage
   - Use: `cp .env.example .env`

2. **`thorchain-1.env`** - Complete configuration for thorchain-1 mainnet
   - Contains all available configuration options
   - Includes advanced P2P, RPC, consensus, and performance tuning settings
   - Use: `cp thorchain-1.env .env`

### Main Configuration Options

The key settings you'll likely want to customize:

- `THORNODE_VERSION`: THORNode version to run (default: v3.6.1)
- `THORNODE_REPO`: Git repository URL for THORNode source code
- `MONIKER`: Your node's moniker/name
- `NETWORK`: Chain ID (default: thorchain-1)
- `SNAPSHOT`: Optional snapshot URL for faster sync
- `SNAPSHOT_API_URL`: API endpoint to find latest snapshots
- `SNAPSHOT_BASE_URL`: Base URL for downloading snapshots
- `SEEDS`: Comma-separated list of seed nodes for peer discovery
- `GENESIS_URL`: URL to download the genesis file
- `EXTRA_FLAGS`: Additional flags to pass to the thornode binary
- `LOG_LEVEL`: Logging level (info, warn, error, trace)

## Ports

The following ports are exposed:

- `27147`: RPC port (THORChain custom)
- `27146`: P2P port (THORChain custom) 
- `9090`: gRPC port
- `9091`: gRPC-Web port
- `1317`: REST API port

## Data Persistence

### Storage Options

THORChain blockchain data can be quite large (1TB+) and grows over time. You have two storage options:

#### Option 1: Docker Volume (Default)
Node data is stored in Docker volumes:
- `thornode-data`: Blockchain data and configuration  
- `thornode-builds`: Built binaries

This is the default and simplest option. Docker manages the storage location.

#### Option 2: Custom Path (Recommended for Production)
For production deployments or when using a dedicated disk:

1. **Prepare your storage location:**
```bash
# Example: Mount a separate disk to /mnt/data
sudo mkdir -p /mnt/data/blockchain
sudo chown 10001:10001 /mnt/data/blockchain
```

2. **Configure custom data directory in `.env`:**
```bash
# Uncomment and set your preferred path
DATA_DIR=/mnt/data/blockchain
```

3. **Benefits of custom path:**
   - Control over storage location
   - Easy to use dedicated high-performance disks
   - Simpler backup and maintenance
   - Data persists even if Docker volumes are removed

#### Typical Production Setup
```bash
# 1. Attach and mount a dedicated SSD
sudo mkfs.ext4 /dev/sdb
sudo mkdir -p /mnt/data
sudo mount /dev/sdb /mnt/data
echo '/dev/sdb /mnt/data ext4 defaults 0 2' | sudo tee -a /etc/fstab

# 2. Prepare thorchain directory
sudo mkdir -p /mnt/data/blockchain
sudo chown 10001:10001 /mnt/data/blockchain

# 3. Configure in .env
echo "DATA_DIR=/mnt/data/blockchain" >> .env

# 4. Start the node
make start
```

## Monitoring

Check node status:
```bash
# Service status
docker compose ps

# Node sync status
curl http://localhost:27147/status

# View logs
docker compose logs thorchain
```

## Updates

To update to a new version:

1. Update `THORNODE_VERSION` in `.env`
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
- Check if ports are already in use: `sudo netstat -tulpn | grep :27147`
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

# For custom data directory
du -sh /mnt/data/blockchain

# For Docker volumes
docker system df
```

### Getting Help

- Check logs: `make logs`
- Node status: `make status`
- Monitor health: `make monitor`
- THORChain Documentation: https://docs.thorchain.org/
- Community Discord: https://discord.gg/thorchain

## Support

Based on the official THORChain documentation: https://docs.thorchain.org/thornodes/fullnode/thornode-linux
