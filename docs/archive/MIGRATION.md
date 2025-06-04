# Migration Guide: THORChain-Docker → Cosmos-Docker

This guide helps existing users migrate from the old THORChain-specific setup to the new generic Cosmos setup.

## What Changed

The project has been converted from a THORChain-specific Docker setup to a generic Cosmos chain setup that supports multiple networks:

### File Changes

| Old File/Directory | New File/Directory | Status |
|-------------------|-------------------|---------|
| `thorchain.yml` | `cosmos.yml` | **Replaced** |
| `thorchain/` | `cosmos/` | **Replaced** |
| `thorchain-1.env` | `thorchain-1.env` | **Updated** (still works) |
| - | `cosmoshub-4.env` | **New** |
| - | `osmosis-1.env` | **New** |
| - | `noble-1.env` | **New** |
| - | `theta-testnet-001.env` | **New** |

### Variable Changes

| Old Variable | New Variable | Notes |
|-------------|-------------|-------|
| `THORNODE_VERSION` | `NODE_VERSION` | Generic version variable |
| `THORNODE_REPO` | `NODE_REPO` | Generic repository variable |
| `THORNODE_LOG_FORMAT` | `NODE_LOG_FORMAT` | Generic log format variable |
| - | `DAEMON_NAME` | **New** - specifies the daemon binary name |

## Migration Steps

### For Existing THORChain Users

If you're currently running THORChain and want to keep the same setup:

1. **Update your .env file:**
   ```bash
   # If you're using the old thorchain.yml, update your .env
   # Replace THORNODE_VERSION with NODE_VERSION
   sed -i 's/THORNODE_VERSION=/NODE_VERSION=/g' .env
   sed -i 's/THORNODE_REPO=/NODE_REPO=/g' .env
   sed -i 's/THORNODE_LOG_FORMAT=/NODE_LOG_FORMAT=/g' .env
   
   # Add the DAEMON_NAME variable
   echo "DAEMON_NAME=thornode" >> .env
   
   # Update COMPOSE_FILE reference
   sed -i 's/thorchain.yml/cosmos.yml/g' .env
   ```

2. **Update your docker-compose commands:**
   ```bash
   # Old way
   docker compose -f thorchain.yml up -d
   
   # New way
   docker compose -f cosmos.yml up -d
   ```

3. **Or simply use the updated environment file:**
   ```bash
   # Use the updated THORChain configuration
   cp thorchain-1.env .env
   make start
   ```

### For New Multi-Chain Setup

If you want to use different Cosmos chains:

1. **Choose a chain configuration:**
   ```bash
   # Cosmos Hub
   cp cosmoshub-4.env .env
   
   # Osmosis
   cp osmosis-1.env .env
   
   # Noble
   cp noble-1.env .env
   
   # Or keep THORChain
   cp thorchain-1.env .env
   ```

2. **Start the node:**
   ```bash
   make start
   ```

### Data Directory Migration

The new setup uses a more organized data directory structure:

```bash
# Old structure
/mnt/data/blockchain/  # All chains mixed together

# New structure  
/mnt/data/blockchain/cosmoshub-4/     # Cosmos Hub data
/mnt/data/blockchain/osmosis-1/       # Osmosis data  
/mnt/data/blockchain/thorchain-1/     # THORChain data
```

If you have existing data, you may need to move it:

```bash
# Example: Move existing THORChain data to new location
sudo mkdir -p /mnt/data/blockchain/thorchain-1
sudo mv /mnt/data/blockchain/* /mnt/data/blockchain/thorchain-1/ 2>/dev/null || true
```

## Verification

After migration, verify everything works:

1. **Run validation:**
   ```bash
   ./validate.sh
   ```

2. **Test configuration:**
   ```bash
   docker compose -f cosmos.yml config --quiet
   ```

3. **Check your setup:**
   ```bash
   make status
   ```

## Rollback (if needed)

If you need to rollback to the old setup:

1. **Restore from git history:**
   ```bash
   git checkout HEAD~1 -- thorchain.yml thorchain/
   ```

2. **Update your .env to use old format:**
   ```bash
   sed -i 's/NODE_VERSION=/THORNODE_VERSION=/g' .env
   sed -i 's/NODE_REPO=/THORNODE_REPO=/g' .env  
   sed -i 's/NODE_LOG_FORMAT=/THORNODE_LOG_FORMAT=/g' .env
   sed -i 's/cosmos.yml/thorchain.yml/g' .env
   ```

## Benefits of the New Setup

- **Multi-chain support**: Run any Cosmos chain with simple configuration
- **Better organization**: Chain-specific data directories and configurations  
- **Easier maintenance**: Generic codebase supports all chains
- **Enhanced development**: Improved development tools and monitoring
- **Future-proof**: Easy to add new Cosmos chains

## Getting Help

- Check the updated [README.md](README.md) for full documentation
- Review [DEVELOPMENT.md](DEVELOPMENT.md) for development setup
- Open an issue if you encounter problems during migration

## Chain-Specific Notes

### THORChain
- Uses custom ports (27147/27146) - automatically configured
- Requires specific build flags - handled automatically
- All existing functionality preserved

### Cosmos Hub
- Standard Cosmos SDK ports (26657/26656)
- Uses `gaiad` binary
- Supports state sync and snapshots

### Osmosis
- Standard ports with custom configuration
- Uses `osmosisd` binary  
- Includes Osmosis-specific optimizations

### Noble
- USDC-focused chain configuration
- Uses `nobled` binary
- Optimized for token transfers
