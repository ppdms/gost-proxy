#!/bin/bash
# Start GOST Lima VM and client as a background service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_NAME="gost"

echo "=== Starting GOST Service ==="

# Check .env exists and read configuration
if [ ! -f "$PROJECT_ROOT/client/.env" ]; then
    echo "ERROR: $PROJECT_ROOT/client/.env not found"
    echo "Copy .env.example and fill in your credentials"
    exit 1
fi

# Read .env to detect servers and their ports
source "$PROJECT_ROOT/client/.env"
SERVERS=($(set | grep -E '^SERVER[0-9]+_CF_CLIENT_ID=' | sed 's/^SERVER\([0-9]*\)_CF_CLIENT_ID=.*/\1/' | sort -n))

if [ ${#SERVERS[@]} -eq 0 ]; then
    echo "ERROR: No servers configured in .env file"
    echo "Define at least one server using SERVER1_CF_CLIENT_ID, SERVER1_CF_CLIENT_SECRET, etc."
    exit 1
fi

echo "Detected ${#SERVERS[@]} server(s), generating Lima VM configuration..."

# Collect all unique ports from configured servers
TCP_PORTS=()
UDP_PORTS=()

for i in "${SERVERS[@]}"; do
    PORT_VAR="SERVER${i}_LOCAL_PORT"
    PORT="${!PORT_VAR}"
    if [ -n "$PORT" ]; then
        TCP_PORTS+=("$PORT")
    fi
done

# Add HTTP proxy port if enabled
if [ "$ENABLE_HTTP_PROXY" = "true" ]; then
    HTTP_PORT="${HTTP_PROXY_PORT:-8080}"
    TCP_PORTS+=("$HTTP_PORT")
fi

# Add Nextcloud ports if configured
if [ -n "$NEXTCLOUD_HOST" ]; then
    NC_HTTP="${NEXTCLOUD_HTTP_PORT:-80}"
    NC_HTTPS="${NEXTCLOUD_HTTPS_PORT:-443}"
    TCP_PORTS+=("$NC_HTTP" "$NC_HTTPS")
fi

# Add SSH forward port if configured
if [ -n "$SSH_FORWARD_HOST" ]; then
    SSH_LOCAL="${SSH_FORWARD_LOCAL_PORT:-2222}"
    TCP_PORTS+=("$SSH_LOCAL")
fi

# Generate lima-gost.yaml from template with dynamic port forwards
LIMA_CONFIG="$SCRIPT_DIR/lima-gost.yaml"
if [ -f "$SCRIPT_DIR/lima-gost.yaml.template" ]; then
    # Write everything before the placeholder
    sed '/# PORTFORWARDS_PLACEHOLDER/q' "$SCRIPT_DIR/lima-gost.yaml.template" | head -n -1 > "$LIMA_CONFIG"
    
    # Write port forwards section
    cat >> "$LIMA_CONFIG" << 'PORTFORWARDS_START'
portForwards:
  - guestSocket: "/tmp/gost.sock"
    hostSocket: "/tmp/gost.sock"
PORTFORWARDS_START

    # Add TCP port forwards
    for port in "${TCP_PORTS[@]}"; do
        cat >> "$LIMA_CONFIG" << PORTFORWARD_ENTRY
  - guestPort: ${port}
    hostPort: ${port}
    proto: tcp
PORTFORWARD_ENTRY
    done

    # Add UDP port forwards
    for port in "${UDP_PORTS[@]}"; do
        cat >> "$LIMA_CONFIG" << PORTFORWARD_ENTRY
  - guestPort: ${port}
    hostPort: ${port}
    proto: udp
PORTFORWARD_ENTRY
    done

    # Write everything after the placeholder
    sed -n '/# PORTFORWARDS_PLACEHOLDER/,$p' "$SCRIPT_DIR/lima-gost.yaml.template" | tail -n +2 >> "$LIMA_CONFIG"

    echo "✓ Generated Lima config with TCP ports: ${TCP_PORTS[*]}, UDP ports: ${UDP_PORTS[*]}"
else
    echo "Warning: lima-gost.yaml.template not found, using existing lima-gost.yaml"
fi

# Extract Zscaler CA certificate from macOS keychain if needed
if [[ "$OSTYPE" == "darwin"* ]]; then
    if security find-certificate -c "Zscaler Root CA" -p /Library/Keychains/System.keychain > /tmp/zscaler-root.crt 2>/dev/null; then
        if [ -s /tmp/zscaler-root.crt ] && grep -q "BEGIN CERTIFICATE" /tmp/zscaler-root.crt; then
            echo "✓ Extracted Zscaler Root CA certificate for VM"
        else
            rm -f /tmp/zscaler-root.crt
        fi
    fi
fi

# Check if VM exists, create if not
if ! limactl list 2>/dev/null | grep -q "^$VM_NAME"; then
    echo "Creating Lima VM '$VM_NAME'..."
    limactl start --name="$VM_NAME" --tty=false "$SCRIPT_DIR/lima-gost.yaml"
else
    # Check if VM is running
    VM_STATUS=$(limactl list "$VM_NAME" 2>/dev/null | tail -n +2 | awk '{print $2}')
    if [ "$VM_STATUS" != "Running" ]; then
        echo "Starting Lima VM '$VM_NAME'..."
        limactl start "$VM_NAME"
    else
        echo "Lima VM '$VM_NAME' already running"
    fi
fi

# Wait for VM to be ready
echo "Waiting for VM to be ready..."
sleep 3

# Detect vzNAT IP address (NTP functionality disabled due to Lima bug #4666)
# echo "Detecting vzNAT interface IP..."
# VZNAT_IP=$(limactl shell "$VM_NAME" ip -4 addr show vznat0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
# if [ -z "$VZNAT_IP" ]; then
#     echo "Warning: Could not detect vzNAT IP, NTP forwarding may not work"
#     VZNAT_IP="192.168.105.2"  # fallback
# else
#     echo "✓ vzNAT IP: $VZNAT_IP"
# fi
# export VZNAT_IP

# Install Go if not present in VM
if ! limactl shell "$VM_NAME" bash -c "command -v go" &>/dev/null; then
    echo "Installing Go in VM..."
    
    # Get latest Go version dynamically
    LATEST_GO=$(curl -sL 'https://go.dev/VERSION?m=text' 2>/dev/null | head -n1 | tr -d '\n')
    GO_VERSION=${LATEST_GO#go}
    
    # Fallback to specific version if API fails
    if [ -z "$GO_VERSION" ]; then
        GO_VERSION="1.23.5"
    fi
    
    GO_ARCH="arm64"
    
    echo "Downloading Go ${GO_VERSION}..."
    
    # Create install script
    cat > /tmp/install-go.sh << 'EOF'
#!/bin/bash
set -e
if [ ! -d '/usr/local/go' ]; then
    cd /tmp
    echo "Fetching Go tarball..."
    wget --progress=dot:giga "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    echo "Extracting Go..."
    sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz"
    
    # Add to PATH
    if ! grep -q '/usr/local/go/bin' /etc/profile; then
        echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile >/dev/null
    fi
    echo "Verifying installation..."
fi
/usr/local/go/bin/go version
EOF
    
    # Substitute variables in the script
    sed -i "s/\${GO_VERSION}/${GO_VERSION}/g" /tmp/install-go.sh
    sed -i "s/\${GO_ARCH}/${GO_ARCH}/g" /tmp/install-go.sh
    
    # Copy and run in VM
    limactl copy /tmp/install-go.sh "$VM_NAME:/tmp/"
    limactl shell "$VM_NAME" bash /tmp/install-go.sh
    rm -f /tmp/install-go.sh
    
    echo "✓ Go ${GO_VERSION} installed"
else
    GO_VERSION=$(limactl shell "$VM_NAME" /usr/local/go/bin/go version 2>/dev/null | awk '{print $3}')
    echo "✓ Go already installed (${GO_VERSION})"
fi

# Check if GOST is installed
if ! limactl shell "$VM_NAME" bash -c "command -v gost" &>/dev/null; then
    echo "GOST not found in VM, installing standard GOST v3..."
    
    # Install GOST using Go
    limactl shell "$VM_NAME" bash -c '
        set -e
        export PATH=$PATH:/usr/local/go/bin
        export GOPATH=$HOME/go
        
        echo "Installing standard GOST v3..."
        go install github.com/go-gost/gost/cmd/gost@latest
        
        sudo cp $HOME/go/bin/gost /usr/local/bin/gost
        sudo chmod +x /usr/local/bin/gost
    '
    echo "✓ GOST installed successfully"
else
    echo "✓ GOST is already installed"
fi

# Prepare config with environment variables
echo "Preparing GOST config..."

# Use centralized config from project root
if [ ! -f "$PROJECT_ROOT/client/.env" ]; then
    echo "ERROR: $PROJECT_ROOT/client/.env not found"
    echo "Copy .env.example and fill in your credentials"
    exit 1
fi

# Copy the entire client directory to VM for dynamic config generation
echo "Copying client configuration to VM..."
limactl shell "$VM_NAME" mkdir -p /tmp/gost-client
limactl copy "$PROJECT_ROOT/client/.env" "$VM_NAME:/tmp/gost-client/"
limactl copy "$PROJECT_ROOT/client/start.sh" "$VM_NAME:/tmp/gost-client/"

# Detect configured servers for validation
source "$PROJECT_ROOT/client/.env"
SERVERS=($(set | grep -E '^SERVER[0-9]+_CF_CLIENT_ID=' | sed 's/^SERVER\([0-9]*\)_CF_CLIENT_ID=.*/\1/' | sort -n))

if [ ${#SERVERS[@]} -eq 0 ]; then
    echo "ERROR: No servers configured in .env file"
    echo "Define at least one server using SERVER1_CF_CLIENT_ID, SERVER1_CF_CLIENT_SECRET, etc."
    exit 1
fi

echo "✓ Found ${#SERVERS[@]} server(s) configured"

# Generate the config dynamically in the VM
echo "Generating configuration in VM..."
limactl shell "$VM_NAME" bash << 'GENCONFIG'
#!/bin/bash
set -e

cd /tmp/gost-client

# Source the .env file
source .env

# Detect all configured servers
SERVERS=($(set | grep -E '^SERVER[0-9]+_CF_CLIENT_ID=' | sed 's/^SERVER\([0-9]*\)_CF_CLIENT_ID=.*/\1/' | sort -n))

# Generate config
cat > /tmp/gost-config.yaml <<'EOF'
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
    
    cat >> /tmp/gost-config.yaml <<SERVICEEOF
  - name: socks5-server${i}
    addr: :${LOCAL_PORT}
    handler:
      type: socks5
      chain: chain-server${i}
      metadata:
        udp: true
    listener:
      type: tcp

SERVICEEOF
done

# Add HTTP proxy if enabled
if [ "$ENABLE_HTTP_PROXY" = "true" ]; then
    HTTP_PORT="${HTTP_PROXY_PORT:-8080}"
    FIRST_SERVER="${SERVERS[0]}"
    
    cat >> /tmp/gost-config.yaml <<SERVICEEOF
  - name: local-http-proxy
    addr: :${HTTP_PORT}
    handler:
      type: http
      chain: chain-server${FIRST_SERVER}
    listener:
      type: tcp

SERVICEEOF
fi

# Add Nextcloud forwards if configured
if [ -n "$NEXTCLOUD_HOST" ]; then
    NC_HTTP="${NEXTCLOUD_HTTP_PORT:-80}"
    NC_HTTPS="${NEXTCLOUD_HTTPS_PORT:-443}"
    FIRST_SERVER="${SERVERS[0]}"

    cat >> /tmp/gost-config.yaml <<SERVICEEOF
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

SERVICEEOF
fi

# Add SSH forward if configured
if [ -n "$SSH_FORWARD_HOST" ]; then
    SSH_LOCAL="${SSH_FORWARD_LOCAL_PORT:-2222}"
    SSH_REMOTE="${SSH_FORWARD_REMOTE_PORT:-22}"
    FIRST_SERVER="${SERVERS[0]}"

    cat >> /tmp/gost-config.yaml <<SERVICEEOF
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

SERVICEEOF
fi

# Generate chains section
cat >> /tmp/gost-config.yaml <<'EOF'

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
    
    cat >> /tmp/gost-config.yaml <<CHAINEOF
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

CHAINEOF
done

# Add logging configuration
cat >> /tmp/gost-config.yaml <<'EOF'
log:
  level: info
  output: stderr
EOF

echo "✓ Configuration generated with ${#SERVERS[@]} server(s)"
GENCONFIG

# Install systemd service if not exists
if ! limactl shell "$VM_NAME" systemctl is-enabled gost.service &>/dev/null; then
    echo "Installing systemd service..."
    
    # Create systemd service file
    cat > /tmp/gost.service << 'SERVICEFILE'
[Unit]
Description=GOST Proxy Client
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -C /tmp/gost-config.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEFILE
    
    # Copy service file to VM
    limactl copy /tmp/gost.service "$VM_NAME:/tmp/"
    limactl shell "$VM_NAME" sudo cp /tmp/gost.service /etc/systemd/system/
    
    # Reload systemd and enable service
    limactl shell "$VM_NAME" sudo systemctl daemon-reload
    limactl shell "$VM_NAME" sudo systemctl enable gost.service
    
    # Clean up local temp file
    rm -f /tmp/gost.service
    
    echo "✓ Systemd service installed and enabled"
fi

# Restart GOST service
echo "Starting GOST service..."
limactl shell "$VM_NAME" sudo systemctl restart gost.service

# Wait for service to start
sleep 2

# Check if GOST is running
if limactl shell "$VM_NAME" systemctl is-active gost.service &>/dev/null; then
    echo "✓ GOST service started successfully"
    echo "✓ System service running as user '$USER'"
    
    # Show available proxies
    echo ""
    echo "Available SOCKS5 proxies:"
    for i in "${SERVERS[@]}"; do
        PORT_VAR="SERVER${i}_LOCAL_PORT"
        LOCAL_PORT="${!PORT_VAR}"
        ADDR_VAR="SERVER${i}_ADDRESS"
        ADDRESS="${!ADDR_VAR}"
        echo "  Server $i: localhost:$LOCAL_PORT (→ $ADDRESS)"
    done
    
    if [ "$ENABLE_HTTP_PROXY" = "true" ]; then
        HTTP_PORT="${HTTP_PROXY_PORT:-8080}"
        echo ""
        echo "HTTP/HTTPS Proxy:"
        echo "  localhost:$HTTP_PORT"
    fi
    
    if [ -n "$NEXTCLOUD_HOST" ]; then
        NC_HTTP="${NEXTCLOUD_HTTP_PORT:-80}"
        NC_HTTPS="${NEXTCLOUD_HTTPS_PORT:-443}"
        echo ""
        echo "Nextcloud Forwards:"
        echo "  HTTP:  localhost:$NC_HTTP → $NEXTCLOUD_HOST:80"
        echo "  HTTPS: localhost:$NC_HTTPS → $NEXTCLOUD_HOST:443"
    fi

    if [ -n "$SSH_FORWARD_HOST" ]; then
        SSH_LOCAL="${SSH_FORWARD_LOCAL_PORT:-2222}"
        SSH_REMOTE="${SSH_FORWARD_REMOTE_PORT:-22}"
        echo ""
        echo "SSH Forward:"
        echo "  localhost:$SSH_LOCAL → $SSH_FORWARD_HOST:$SSH_REMOTE"
    fi

    # Configure apt to use GOST proxy and run upgrades in background
    echo ""
    echo "Setting up apt to use GOST proxy..."
    limactl shell "$VM_NAME" bash << 'APTSETUP'
set -e

# Configure apt to use SOCKS5 proxy
sudo tee /etc/apt/apt.conf.d/80proxy > /dev/null << 'EOF'
Acquire::http::Proxy "socks5h://127.0.0.1:1080";
Acquire::https::Proxy "socks5h://127.0.0.1:1080";
EOF

echo "✓ Apt configured to use GOST proxy"

# Create background upgrade script
sudo tee /usr/local/bin/upgrade-via-proxy.sh > /dev/null << 'EOF'
#!/bin/bash
set -e

echo "=== Package Management via GOST Proxy ==="
echo "Starting package operations through tunnel..."

# Update package lists
apt-get update

# Upgrade all packages for security
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

# Install unattended-upgrades (chrony disabled due to Lima bug #4666)
apt-get install -y --no-install-recommends \
  unattended-upgrades \
  apt-listchanges

# Configure unattended-upgrades for automatic security updates
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'UNATTENDED'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
UNATTENDED

# Enable automatic security updates
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'AUTOUPGRADES'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOUPGRADES

# NTP/chrony configuration disabled due to Lima bug #4666 (NTP socket leak)
# VZNAT_IP=$(ip -4 addr show vznat0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
# cat > /etc/chrony/sources.d/gost-ntp.sources << CHRONYSRC
# server ${VZNAT_IP} iburst
# CHRONYSRC
# systemctl restart chrony

echo "✓ Package upgrades complete with automatic updates enabled"
EOF

sudo chmod +x /usr/local/bin/upgrade-via-proxy.sh

# Run upgrade in background (redirect to journal via systemd-cat)
echo "Starting package upgrade in background (through GOST tunnel)..."
nohup sudo bash -c '/usr/local/bin/upgrade-via-proxy.sh 2>&1 | systemd-cat -t upgrade-via-proxy' > /dev/null 2>&1 &

echo "✓ Background upgrade started (check: journalctl -t upgrade-via-proxy -f)"
APTSETUP

    echo "✓ Apt proxy configured, upgrades running in background"
    
    echo ""
    echo "Commands:"
    echo "  Status:     limactl shell $VM_NAME sudo systemctl status gost.service"
    echo "  Logs:       limactl shell $VM_NAME sudo journalctl -u gost.service -f"
    echo "  Upgrade:    limactl shell $VM_NAME sudo journalctl -t upgrade-via-proxy -f"
    # echo "  NTP:        limactl shell $VM_NAME sudo chronyc tracking"
    echo "  Stop:       limactl shell $VM_NAME sudo systemctl stop gost.service"
    echo "  Restart:    limactl shell $VM_NAME sudo systemctl restart gost.service"
    echo ""
    echo "Test proxies:"
    echo "  SOCKS5:     curl --socks5-hostname localhost:1080 https://ifconfig.me"
    if [ "$ENABLE_HTTP_PROXY" = "true" ]; then
        HTTP_PORT="${HTTP_PROXY_PORT:-8080}"
        echo "  HTTP:       curl --proxy http://localhost:$HTTP_PORT https://ifconfig.me"
    fi
else
    echo "✗ Failed to start GOST service"
    echo "Check status: limactl shell $VM_NAME sudo systemctl status gost.service"
    echo "Check logs:   limactl shell $VM_NAME sudo journalctl -u gost.service -n 50"
    exit 1
fi
