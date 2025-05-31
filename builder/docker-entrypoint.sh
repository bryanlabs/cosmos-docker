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

# Download the correct WasmVM library for musl (if needed by the chain)
echo "Downloading WasmVM library for musl..."
go mod download

# Check if this chain uses WasmVM
if grep -q "github.com/CosmWasm/wasmvm" go.mod; then
    echo "Chain uses WasmVM, downloading musl library..."
    WASMVM_VERSION=$(go list -m github.com/CosmWasm/wasmvm/v2 | cut -d ' ' -f 2)
    echo "WasmVM version: $WASMVM_VERSION"

    # Download the musl-compatible static library
    wget -q https://github.com/CosmWasm/wasmvm/releases/download/$WASMVM_VERSION/libwasmvm_muslc.$(uname -m).a \
      -O /lib/libwasmvm_muslc.$(uname -m).a

    # Verify checksum
    wget -q https://github.com/CosmWasm/wasmvm/releases/download/"$WASMVM_VERSION"/checksums.txt -O /tmp/checksums.txt
    sha256sum /lib/libwasmvm_muslc.$(uname -m).a | grep $(cat /tmp/checksums.txt | grep libwasmvm_muslc.$(uname -m) | cut -d ' ' -f 1)

    # Replace the glibc version with musl version in the Go module cache
    WASMVM_PATH=$(go list -m -f '{{.Dir}}' github.com/CosmWasm/wasmvm/v2)
    echo "Replacing WasmVM library at: $WASMVM_PATH"
    cp /lib/libwasmvm_muslc.$(uname -m).a $WASMVM_PATH/internal/api/libwasmvm.$(uname -m).a
    rm -f $WASMVM_PATH/internal/api/libwasmvm.*.so
else
    echo "Chain does not use WasmVM, skipping WasmVM setup..."
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
