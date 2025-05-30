#!/usr/bin/env bash

# Test script to verify user permission changes

echo "=== Testing User Permission Configuration ==="
echo ""

echo "📋 Current host user details:"
echo "User: $(whoami)"
echo "UID: $(id -u)"
echo "GID: $(id -g)"
echo "Groups: $(groups)"
echo ""

echo "🔧 Testing environment variable setup:"
export HOST_UID=$(id -u)
export HOST_GID=$(id -g)
echo "HOST_UID: $HOST_UID"
echo "HOST_GID: $HOST_GID"
echo ""

echo "🐳 Testing Docker Compose file syntax with user variables:"
if command -v docker-compose >/dev/null 2>&1; then
    HOST_UID=$HOST_UID HOST_GID=$HOST_GID docker-compose -f cosmos.yml config --quiet >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✅ Docker Compose configuration is valid with user variables"
    else
        echo "❌ Docker Compose configuration failed with user variables"
        exit 1
    fi
else
    echo "⚠️  docker-compose not available, skipping syntax check"
fi

echo ""
echo "📝 Verifying no hardcoded 10001 references remain:"
if grep -r "10001" . --exclude-dir=.git --exclude="*.log" --exclude="test-user-permissions.sh" >/dev/null 2>&1; then
    echo "❌ Found remaining 10001 references:"
    grep -r "10001" . --exclude-dir=.git --exclude="*.log" --exclude="test-user-permissions.sh"
    exit 1
else
    echo "✅ No hardcoded 10001 references found"
fi

echo ""
echo "🎉 All tests passed! The system will now use your current user ($(whoami)) instead of hardcoded UID 10001"
