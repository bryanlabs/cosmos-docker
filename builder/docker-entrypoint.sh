#!/usr/bin/env bash
set -euo pipefail

THORNODE_VERSION=${THORNODE_VERSION:-v3.5.6}

# Check if binary already exists
if [ -f "/builds/thornode-${THORNODE_VERSION}" ] && [ "$FORCE_REBUILD" != "true" ]; then
    echo "Binary thornode-${THORNODE_VERSION} already exists and FORCE_REBUILD is false. Skipping build."
    exit 0
fi

echo "Building THORNode version ${THORNODE_VERSION}"

# Clone the repository
THORNODE_REPO="${THORNODE_REPO:-https://gitlab.com/thorchain/thornode}"
echo "Cloning repository from: $THORNODE_REPO"
git clone --branch ${THORNODE_VERSION} "$THORNODE_REPO" /src/thornode
cd /src/thornode

# Download the correct WasmVM library for musl
echo "Downloading WasmVM library for musl..."
go mod download
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

# Create symlink for docker (required by build process)
ln -fs /usr/bin/true docker
export PATH=$(pwd):$PATH

# Build the binary with static linking and version info
echo "Building thornode binary..."
VERSION_NUM=${THORNODE_VERSION#v}  # Remove 'v' prefix
GIT_COMMIT=$(git rev-parse HEAD)

# Build directly with go build and version flags
CGO_ENABLED=1 go build -mod=readonly -tags "netgo,ledger,muslc" \
  -ldflags "-w -s -linkmode=external -extldflags '-Wl,-z,muldefs -static' \
  -X gitlab.com/thorchain/thornode/v3/constants.Version=${VERSION_NUM} \
  -X gitlab.com/thorchain/thornode/v3/constants.GitCommit=${GIT_COMMIT} \
  -X github.com/cosmos/cosmos-sdk/version.Name=THORChain \
  -X github.com/cosmos/cosmos-sdk/version.AppName=thornode \
  -X github.com/cosmos/cosmos-sdk/version.Version=${VERSION_NUM} \
  -X github.com/cosmos/cosmos-sdk/version.Commit=${GIT_COMMIT} \
  -X github.com/cosmos/cosmos-sdk/version.BuildTags=netgo,ledger,muslc" \
  -trimpath -o /builds/thornode-${THORNODE_VERSION} ./cmd/thornode

# Verify the build was successful
if [ ! -f "/builds/thornode-${THORNODE_VERSION}" ]; then
    echo "Build failed - binary not found"
    exit 1
fi

echo "Build complete: thornode-${THORNODE_VERSION}"
