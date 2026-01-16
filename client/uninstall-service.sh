#!/bin/bash
# Uninstall GOST client LaunchAgent service

set -e

SERVICE_NAME="com.gost.proxy.client"
PLIST_FILE="$HOME/Library/LaunchAgents/${SERVICE_NAME}.plist"

if [ -f "$PLIST_FILE" ]; then
    echo "Stopping and unloading service..."
    launchctl unload "$PLIST_FILE" 2>/dev/null || true
    
    echo "Removing plist file..."
    rm "$PLIST_FILE"
    
    echo "Service uninstalled successfully"
else
    echo "Service not found"
fi
