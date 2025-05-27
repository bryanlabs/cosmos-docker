# THORChain Docker

Run THORChain fullnode in Docker Compose.

This Docker Compose setup provides a complete THORChain fullnode environment based on the official THORNode Linux installation guide.

## Quick Start

1. Copy the environment file:
```bash
cp default.env .env
```

2. Optionally, edit `.env` to customize your setup:
```bash
nano .env
```

3. Start the node:
```bash
docker compose up -d
```

4. Monitor logs:
```bash
docker compose logs -f thorchain
```

## Configuration

The main configuration options in `.env`:

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

- `26657`: RPC port (Cosmos standard)
- `26656`: P2P port (Cosmos standard) 
- `9090`: gRPC port
- `9091`: gRPC-Web port
- `1317`: REST API port

## Data Persistence

Node data is stored in Docker volumes:

- `thornode-data`: Blockchain data and configuration
- `thornode-builds`: Built binaries

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

## Advanced Configuration

For production deployments with Traefik reverse proxy, additional configuration files are available. See the labels in `thorchain.yml` for Traefik integration.

## Support

Based on the official THORChain documentation: https://docs.thorchain.org/thornodes/fullnode/thornode-linux
