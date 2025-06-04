# User Permission Migration Summary

## Changes Made

This migration removes all hardcoded UID 10001 references and makes the system work with the current host user (ubuntu, debian, centos, etc.).

### Files Modified:

1. **cosmos/Dockerfile.source**:
   - Changed `ARG UID=10001` to `ARG UID=1000` with `ARG GID=1000`
   - Updated user creation to use both UID and GID
   - Now creates a group first, then adds user to that group

2. **cosmos.yml**:
   - Added `UID=${HOST_UID:-1000}` and `GID=${HOST_GID:-1000}` build args
   - These are passed to the Docker build process

3. **Makefile**:
   - Updated all `docker compose` commands to include `HOST_UID=$(id -u) HOST_GID=$(id -g)`
   - Changed `sudo chown 10001:10001` to `sudo chown $(id -u):$(id -g)`
   - Modified targets: start, dev, dev-tools, build, update, watch-builder-switch, setup-data-dir

4. **README.md**:
   - Updated all documentation examples
   - Changed `sudo chown 10001:10001` to `sudo chown $(id -u):$(id -g)`
   - Updated troubleshooting section

5. **.env.example**:
   - Added documentation about automatic HOST_UID/HOST_GID usage

### How It Works:

1. **Build Time**: 
   - HOST_UID and HOST_GID are automatically set to current user's values
   - Docker container user is created with matching UID/GID

2. **Runtime**:
   - Container runs as user with same UID/GID as host user
   - File permissions work seamlessly between host and container

3. **Data Directories**:
   - `make setup-data-dir` uses current user's UID/GID
   - No more permission issues with mounted volumes

### Benefits:

- ✅ Works with ubuntu, debian, centos, and any Linux distribution
- ✅ No more hardcoded UID 10001 conflicts
- ✅ Seamless file permissions between host and container
- ✅ No manual chown commands needed for most use cases
- ✅ Follows Docker best practices for user management

### Usage:

The system now automatically detects and uses your current user. Simply run:

```bash
# Copy your chain configuration
cp cosmoshub-4.env .env

# Start the node (user permissions handled automatically)
make start
```

For custom data directories:
```bash
# Set up data directory with correct permissions
make setup-data-dir

# Start the node
make start
```

The system will work correctly whether you're running as:
- ubuntu (UID 1000)
- debian user (UID 1000) 
- centos user (UID 1000)
- Any other user with any UID

No more manual permission fixes needed!
