#!/bin/bash
# Start GOST Lima VM and client as a background service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_NAME="gost"

echo "=== Starting GOST Service ==="

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

# Load credentials from centralized .env
source "$PROJECT_ROOT/client/.env"

# Check required variables
if [ -z "$CF_ACCESS_CLIENT_ID" ] || [ -z "$CF_ACCESS_CLIENT_SECRET" ]; then
    echo "ERROR: Missing Cloudflare Access credentials in .env"
    exit 1
fi

# Set defaults
GOST_SERVER_ADDRESS="${GOST_SERVER_ADDRESS:-proxy.example.com:443}"
GOST_SERVER_HOSTNAME="${GOST_SERVER_HOSTNAME:-${GOST_SERVER_ADDRESS%%:*}}"

# Create config with substituted values using centralized config
export CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET GOST_SERVER_ADDRESS GOST_SERVER_HOSTNAME
envsubst < "$PROJECT_ROOT/client/config.yaml" > /tmp/gost-config-subst.yaml

# Copy config to VM
limactl copy /tmp/gost-config-subst.yaml "$VM_NAME:/tmp/gost-config.yaml"
rm -f /tmp/gost-config-subst.yaml

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
    echo "✓ SOCKS5 proxy available at localhost:1080"
    
    # Enable and start the post-GOST upgrade service (if it exists and isn't already enabled)
    if limactl shell "$VM_NAME" bash -c "[ -f /etc/systemd/system/upgrade-after-gost.service ]" 2>/dev/null; then
        if ! limactl shell "$VM_NAME" systemctl is-enabled upgrade-after-gost.service &>/dev/null; then
            echo ""
            echo "Enabling automatic package upgrades after GOST startup..."
            limactl shell "$VM_NAME" sudo systemctl enable upgrade-after-gost.service
            limactl shell "$VM_NAME" sudo systemctl start upgrade-after-gost.service &
            echo "✓ Package upgrade service enabled (running in background)"
        fi
    fi
    
    echo ""
    echo "Commands:"
    echo "  Status:     limactl shell $VM_NAME sudo systemctl status gost.service"
    echo "  Logs:       limactl shell $VM_NAME sudo journalctl -u gost.service -f"
    echo "  Stop:       limactl shell $VM_NAME sudo systemctl stop gost.service"
    echo "  Restart:    limactl shell $VM_NAME sudo systemctl restart gost.service"
    echo "  Disable:    limactl shell $VM_NAME sudo systemctl disable gost.service"
    echo "  Test:       curl --socks5-hostname localhost:1080 https://ifconfig.me"
else
    echo "✗ Failed to start GOST service"
    echo "Check status: limactl shell $VM_NAME sudo systemctl status gost.service"
    echo "Check logs:   limactl shell $VM_NAME sudo journalctl -u gost.service -n 50"
    exit 1
fi
