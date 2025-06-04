#!/usr/bin/env bash
set -euo pipefail

NODE_VERSION=${NODE_VERSION:-v1.0.0}
DAEMON_NAME=${DAEMON_NAME:-cosmos}
FORCE_REBUILD=${FORCE_REBUILD:-false}

# Check if binary already exists
if [ -f "/builds/${DAEMON_NAME}-${NODE_VERSION}" ] && [ "$FORCE_REBUILD" != "true" ]; then
    echo "Binary ${DAEMON_NAME}-${NODE_VERSION} already exists and FORCE_REBUILD is false. Skipping build."
    exit 0
fi

echo "Building ${DAEMON_NAME} version ${NODE_VERSION}"

# Clone the repository
NODE_REPO="${NODE_REPO:-https://github.com/cosmos/cosmos-sdk}"
echo "Cloning repository from: $NODE_REPO"
git clone --branch ${NODE_VERSION} "$NODE_REPO" /src/node
cd /src/node

# Check if this chain uses WasmVM and detect version before downloading modules
WASMVM_VERSION=""
WASMVM_MODULE=""
USES_WASMVM=false

if grep -q "github.com/CosmWasm/wasmvm" go.mod; then
    echo "Chain uses WasmVM, detecting version..."
    USES_WASMVM=true
    
    # Detect WasmVM version (v1 or v2) by checking go.mod directly
    if grep -q "github.com/CosmWasm/wasmvm/v2" go.mod; then
        WASMVM_MODULE="github.com/CosmWasm/wasmvm/v2"
        echo "Detected WasmVM v2 in go.mod"
    elif grep -q "github.com/CosmWasm/wasmvm" go.mod; then
        WASMVM_MODULE="github.com/CosmWasm/wasmvm"
        echo "Detected WasmVM v1 in go.mod"
    else
        echo "Error: Could not detect WasmVM version in go.mod"
        exit 1
    fi
else
    echo "Chain does not use WasmVM"
fi

# Download dependencies
echo "Downloading Go modules..."
go mod download

if [ "$USES_WASMVM" = true ]; then
    echo "Setting up WasmVM musl library..."
    
    # Get the actual version from go.mod
    WASMVM_VERSION=$(go list -m $WASMVM_MODULE | cut -d ' ' -f 2)
    echo "WasmVM version: $WASMVM_VERSION"

    # Download the musl-compatible static library
    echo "Downloading WasmVM musl library..."
    if ! wget -q https://github.com/CosmWasm/wasmvm/releases/download/$WASMVM_VERSION/libwasmvm_muslc.$(uname -m).a \
      -O /lib/libwasmvm_muslc.$(uname -m).a; then
        echo "Error: Failed to download WasmVM musl library"
        exit 1
    fi

    # Verify checksum
    echo "Verifying WasmVM library checksum..."
    if ! wget -q https://github.com/CosmWasm/wasmvm/releases/download/"$WASMVM_VERSION"/checksums.txt -O /tmp/checksums.txt; then
        echo "Warning: Could not download checksums file, skipping verification"
    else
        if ! sha256sum /lib/libwasmvm_muslc.$(uname -m).a | grep $(cat /tmp/checksums.txt | grep libwasmvm_muslc.$(uname -m) | cut -d ' ' -f 1); then
            echo "Warning: Checksum verification failed, but continuing build"
        else
            echo "Checksum verification passed"
        fi
    fi

    # Replace the glibc version with musl version in the Go module cache
    WASMVM_PATH=$(go list -m -f '{{.Dir}}' $WASMVM_MODULE)
    echo "Replacing WasmVM library at: $WASMVM_PATH"
    
    if [ ! -d "$WASMVM_PATH" ]; then
        echo "Error: WasmVM path not found: $WASMVM_PATH"
        exit 1
    fi
    
    # Create the internal/api directory if it doesn't exist
    mkdir -p "$WASMVM_PATH/internal/api"
    
    # Copy the library with both expected names
    cp /lib/libwasmvm_muslc.$(uname -m).a $WASMVM_PATH/internal/api/libwasmvm.$(uname -m).a
    cp /lib/libwasmvm_muslc.$(uname -m).a $WASMVM_PATH/internal/api/libwasmvm_muslc.a
    rm -f $WASMVM_PATH/internal/api/libwasmvm.*.so
fi

# Create symlink for docker (required by build process)
ln -fs /usr/bin/true docker
export PATH=$(pwd):$PATH

# Build the binary with static linking and version info
echo "Building ${DAEMON_NAME} binary..."
VERSION_NUM=${NODE_VERSION#v}  # Remove 'v' prefix
GIT_COMMIT=$(git rev-parse HEAD)

# Determine the correct build command based on chain structure
BUILD_CMD=""
if [ -f "cmd/${DAEMON_NAME}/main.go" ]; then
    BUILD_CMD="./cmd/${DAEMON_NAME}"
elif [ -f "cmd/thornode/main.go" ]; then
    BUILD_CMD="./cmd/thornode"
elif [ -f "cmd/gaiad/main.go" ]; then
    BUILD_CMD="./cmd/gaiad"
elif [ -f "cmd/osmosisd/main.go" ]; then
    BUILD_CMD="./cmd/osmosisd"
elif [ -f "cmd/simd/main.go" ]; then
    BUILD_CMD="./cmd/simd"
else
    echo "Could not determine build command. Looking for main.go files..."
    find cmd -name "main.go" -type f | head -5
    echo "Please set BUILD_TARGET environment variable"
    exit 1
fi

echo "Using build command: $BUILD_CMD"

# Determine ldflags based on the project structure
LDFLAGS="-w -s -linkmode=external -extldflags '-Wl,-z,muldefs -static'"

# Try to detect the correct version path
if grep -q "gitlab.com/thorchain/thornode" go.mod; then
    LDFLAGS="$LDFLAGS -X gitlab.com/thorchain/thornode/v3/constants.Version=${VERSION_NUM}"
    LDFLAGS="$LDFLAGS -X gitlab.com/thorchain/thornode/v3/constants.GitCommit=${GIT_COMMIT}"
    LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.Name=THORChain"
    LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.AppName=thornode"
elif grep -q "github.com/terra-money/core" go.mod; then
    LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.Name=terra"
    LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.AppName=terrad"
elif grep -q "github.com/Team-Kujira/core" go.mod; then
    LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.Name=kujira"
    LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.AppName=kujirad"
elif grep -q "github.com/cosmos/cosmos-sdk" go.mod; then
    LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.Name=${DAEMON_NAME}"
    LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.AppName=${DAEMON_NAME}"
fi

# Common version flags
LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.Version=${VERSION_NUM}"
LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.Commit=${GIT_COMMIT}"
LDFLAGS="$LDFLAGS -X github.com/cosmos/cosmos-sdk/version.BuildTags=netgo,ledger,muslc"

# Build directly with go build and version flags
CGO_ENABLED=1 go build -mod=readonly -tags "netgo,ledger,muslc" \
  -ldflags "$LDFLAGS" \
  -trimpath -o /builds/${DAEMON_NAME}-${NODE_VERSION} $BUILD_CMD

# Verify the build was successful
if [ ! -f "/builds/${DAEMON_NAME}-${NODE_VERSION}" ]; then
    echo "Build failed - binary not found"
    exit 1
fi

echo "Build complete: ${DAEMON_NAME}-${NODE_VERSION}"
