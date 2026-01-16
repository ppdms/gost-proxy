#!/bin/bash
# Install GOST client as a macOS LaunchAgent service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="com.gost.proxy.client"
PLIST_FILE="$HOME/Library/LaunchAgents/${SERVICE_NAME}.plist"

# Check if .env exists
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    echo "ERROR: .env file not found"
    echo "Please create .env from .env.example and configure it first"
    exit 1
fi

# Load environment variables
source "$SCRIPT_DIR/.env"

# Check for GOST binary
if ! command -v gost &> /dev/null; then
    echo "ERROR: gost binary not found in PATH"
    echo "Please install GOST v3 first"
    exit 1
fi

GOST_PATH=$(command -v gost)

echo "Creating LaunchAgent plist..."
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SERVICE_NAME}</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SCRIPT_DIR}/start.sh</string>
    </array>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>CF_ACCESS_CLIENT_ID</key>
        <string>${CF_ACCESS_CLIENT_ID}</string>
        <key>CF_ACCESS_CLIENT_SECRET</key>
        <string>${CF_ACCESS_CLIENT_SECRET}</string>
        <key>GOST_SERVER_ADDRESS</key>
        <string>${GOST_SERVER_ADDRESS}</string>
        <key>GOST_SERVER_HOSTNAME</key>
        <string>${GOST_SERVER_HOSTNAME:-${GOST_SERVER_ADDRESS%%:*}}</string>
        <key>GOST_LOCAL_PORT</key>
        <string>${GOST_LOCAL_PORT:-1080}</string>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    
    <key>WorkingDirectory</key>
    <string>${SCRIPT_DIR}</string>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>${HOME}/Library/Logs/gost-client.log</string>
    
    <key>StandardErrorPath</key>
    <string>${HOME}/Library/Logs/gost-client-error.log</string>
</dict>
</plist>
EOF

echo "LaunchAgent created at: $PLIST_FILE"
echo ""
echo "To start the service:"
echo "  launchctl load \"$PLIST_FILE\""
echo ""
echo "To stop the service:"
echo "  launchctl unload \"$PLIST_FILE\""
echo ""
echo "To check status:"
echo "  launchctl list | grep gost"
echo ""
echo "View logs at:"
echo "  ~/Library/Logs/gost-client.log"
echo "  ~/Library/Logs/gost-client-error.log"
