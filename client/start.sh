#!/bin/bash
# Start GOST v3 client with Cloudflare Access headers
# Supports multiple GOST servers configured via SERVER*_ environment variables

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

# Function to detect all configured servers
detect_servers() {
    set | grep -E '^SERVER[0-9]+_CF_CLIENT_ID=' | sed 's/^SERVER\([0-9]*\)_CF_CLIENT_ID=.*/\1/' | sort -n
}

# Get list of configured servers
SERVERS=($(detect_servers))

if [ ${#SERVERS[@]} -eq 0 ]; then
    echo "ERROR: No servers configured in .env file"
    echo "Define at least one server using SERVER1_CF_CLIENT_ID, SERVER1_CF_CLIENT_SECRET, etc."
    exit 1
fi

echo "=== Starting GOST Client ==="
echo "Found ${#SERVERS[@]} server(s) configured"
echo ""

# Generate dynamic config
CONFIG_FILE=$(mktemp /tmp/gost-config.XXXXXX.yaml)
trap "rm -f $CONFIG_FILE" EXIT

# Start with template or basic header
cat > "$CONFIG_FILE" <<'EOF'
# GOST v3 Configuration (auto-generated)
services:
EOF

# Generate a service for each server
for i in "${SERVERS[@]}"; do
    CF_ID_VAR="SERVER${i}_CF_CLIENT_ID"
    CF_SECRET_VAR="SERVER${i}_CF_CLIENT_SECRET"
    ADDR_VAR="SERVER${i}_ADDRESS"
    HOSTNAME_VAR="SERVER${i}_HOSTNAME"
    PORT_VAR="SERVER${i}_LOCAL_PORT"
    
    CF_ID="${!CF_ID_VAR}"
    CF_SECRET="${!CF_SECRET_VAR}"
    ADDRESS="${!ADDR_VAR}"
    HOSTNAME="${!HOSTNAME_VAR:-${ADDRESS%%:*}}"
    LOCAL_PORT="${!PORT_VAR}"
    
    # Validate required variables
    if [ -z "$CF_ID" ] || [ -z "$CF_SECRET" ] || [ -z "$ADDRESS" ] || [ -z "$LOCAL_PORT" ]; then
        echo "ERROR: Incomplete configuration for SERVER${i}"
        echo "Required: SERVER${i}_CF_CLIENT_ID, SERVER${i}_CF_CLIENT_SECRET, SERVER${i}_ADDRESS, SERVER${i}_LOCAL_PORT"
        exit 1
    fi
    
    echo "Server $i: $ADDRESS -> localhost:$LOCAL_PORT"
    
    # Add SOCKS5 service for this server
    cat >> "$CONFIG_FILE" <<EOF
  - name: socks5-server${i}
    addr: :${LOCAL_PORT}
    handler:
      type: socks5
      chain: chain-server${i}
      metadata:
        udp: true
    listener:
      type: tcp

EOF
done

# Add HTTP proxy if enabled
if [ "$ENABLE_HTTP_PROXY" = "true" ]; then
    HTTP_PORT="${HTTP_PROXY_PORT:-8080}"
    # Use the first server's chain
    FIRST_SERVER="${SERVERS[0]}"
    echo "Enabling HTTP proxy on port $HTTP_PORT (via server $FIRST_SERVER)"
    
    cat >> "$CONFIG_FILE" <<EOF
  - name: local-http-proxy
    addr: :${HTTP_PORT}
    handler:
      type: http
      chain: chain-server${FIRST_SERVER}
    listener:
      type: tcp

EOF
fi

# Add Nextcloud forwards if configured
if [ -n "$NEXTCLOUD_HOST" ]; then
    NC_HTTP="${NEXTCLOUD_HTTP_PORT:-80}"
    NC_HTTPS="${NEXTCLOUD_HTTPS_PORT:-443}"
    FIRST_SERVER="${SERVERS[0]}"
    echo "Enabling Nextcloud forwarding: HTTP:$NC_HTTP, HTTPS:$NC_HTTPS -> $NEXTCLOUD_HOST (via server $FIRST_SERVER)"

    cat >> "$CONFIG_FILE" <<EOF
  - name: nextcloud-forward-http
    addr: :${NC_HTTP}
    handler:
      type: tcp
      chain: chain-server${FIRST_SERVER}
    listener:
      type: tcp
    forwarder:
      nodes:
        - name: nextcloud-server
          addr: ${NEXTCLOUD_HOST}:80

  - name: nextcloud-forward-https
    addr: :${NC_HTTPS}
    handler:
      type: tcp
      chain: chain-server${FIRST_SERVER}
    listener:
      type: tcp
    forwarder:
      nodes:
        - name: nextcloud-server
          addr: ${NEXTCLOUD_HOST}:443

EOF
fi

# Add SSH forward if configured
if [ -n "$SSH_FORWARD_HOST" ]; then
    SSH_LOCAL="${SSH_FORWARD_LOCAL_PORT:-2222}"
    SSH_REMOTE="${SSH_FORWARD_REMOTE_PORT:-22}"
    FIRST_SERVER="${SERVERS[0]}"
    echo "Enabling SSH forwarding: localhost:$SSH_LOCAL -> $SSH_FORWARD_HOST:$SSH_REMOTE (via server $FIRST_SERVER)"

    cat >> "$CONFIG_FILE" <<EOF
  - name: ssh-forward
    addr: :${SSH_LOCAL}
    handler:
      type: tcp
      chain: chain-server${FIRST_SERVER}
    listener:
      type: tcp
    forwarder:
      nodes:
        - name: ssh-target
          addr: ${SSH_FORWARD_HOST}:${SSH_REMOTE}

EOF
fi


echo ""

# Generate chains section
cat >> "$CONFIG_FILE" <<'EOF'
chains:
EOF

# Generate a chain for each server
for i in "${SERVERS[@]}"; do
    CF_ID_VAR="SERVER${i}_CF_CLIENT_ID"
    CF_SECRET_VAR="SERVER${i}_CF_CLIENT_SECRET"
    ADDR_VAR="SERVER${i}_ADDRESS"
    HOSTNAME_VAR="SERVER${i}_HOSTNAME"
    
    CF_ID="${!CF_ID_VAR}"
    CF_SECRET="${!CF_SECRET_VAR}"
    ADDRESS="${!ADDR_VAR}"
    HOSTNAME="${!HOSTNAME_VAR:-${ADDRESS%%:*}}"
    
    cat >> "$CONFIG_FILE" <<EOF
  - name: chain-server${i}
    hops:
      - name: hop-server${i}
        nodes:
          - name: node-server${i}
            addr: ${ADDRESS}
            connector:
              type: http
            dialer:
              type: wss
              tls:
                serverName: ${HOSTNAME}
              metadata:
                header:
                  CF-Access-Client-Id: "${CF_ID}"
                  CF-Access-Client-Secret: "${CF_SECRET}"

EOF
done

# Add logging configuration
cat >> "$CONFIG_FILE" <<'EOF'
log:
  level: info
  output: stderr
EOF

echo "Configuration generated successfully"
echo "Starting GOST..."
echo ""

# Start GOST
gost -C "$CONFIG_FILE"
