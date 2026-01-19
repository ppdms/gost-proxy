#!/bin/bash
# Run GOST v3 server for Cloudflare Tunnel

set -e

CONTAINER_NAME="gost-server"
CONFIG_FILE="config.yaml"

echo "=== Starting GOST v3 Server ==="

# Check if config file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Configuration file $CONFIG_FILE not found"
    echo "Create it with PHT listener configuration"
    exit 1
fi

# Stop and remove existing container if running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Stopping and removing existing container..."
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
fi

# Run the container with config file
echo "Pulling GOST v3 image..."
docker pull gogost/gost:latest

docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --sysctl net.ipv6.conf.all.disable_ipv6=1 \
    --sysctl net.ipv6.conf.default.disable_ipv6=1 \
    -p 127.0.0.1:8080:8080 \
    -v "$(pwd)/$CONFIG_FILE:/etc/gost/config.yaml:ro" \
    gogost/gost:latest \
    -C /etc/gost/config.yaml

echo ""
echo "=== GOST v3 Server Started ==="
echo "Container: $CONTAINER_NAME"
echo "Listening on: 127.0.0.1:8080"
echo "Config: $CONFIG_FILE"
echo ""
echo "Make sure your Cloudflare Tunnel points to http://localhost:8080"
echo "Example: cloudflared tunnel --url http://localhost:8080"
echo ""
echo "To view logs: docker logs -f $CONTAINER_NAME"
echo "To stop: docker stop $CONTAINER_NAME"
