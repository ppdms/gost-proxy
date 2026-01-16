#!/bin/bash
# Start GOST v3 client with Cloudflare Access headers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load configuration from .env file
if [ -f .env ]; then
    source .env
else
    echo "ERROR: .env file not found"
    echo "Copy .env.example to .env and fill in your credentials"
    exit 1
fi

# Check for required environment variables
if [ -z "$CF_ACCESS_CLIENT_ID" ] || [ -z "$CF_ACCESS_CLIENT_SECRET" ]; then
    echo "ERROR: Missing Cloudflare Access credentials in .env file"
    exit 1
fi

if [ -z "$GOST_SERVER_ADDRESS" ]; then
    echo "ERROR: GOST_SERVER_ADDRESS not set in .env file"
    exit 1
fi

# Set defaults
GOST_SERVER_HOSTNAME="${GOST_SERVER_HOSTNAME:-${GOST_SERVER_ADDRESS%%:*}}"
GOST_LOCAL_PORT="${GOST_LOCAL_PORT:-1080}"

echo "=== Starting GOST Client ==="
echo "Server: $GOST_SERVER_ADDRESS"
echo "Local SOCKS5: localhost:$GOST_LOCAL_PORT"
echo ""

# Substitute environment variables in config
export CF_ACCESS_CLIENT_ID
export CF_ACCESS_CLIENT_SECRET
export GOST_SERVER_ADDRESS
export GOST_SERVER_HOSTNAME

CONFIG_FILE=$(mktemp)
trap "rm -f $CONFIG_FILE" EXIT

envsubst < config.yaml > "$CONFIG_FILE"

# Start GOST
gost -C "$CONFIG_FILE"
