#!/bin/bash
# Quick reference for GOST Proxy management

cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║              GOST Proxy - Quick Reference                      ║
╚════════════════════════════════════════════════════════════════╝

📍 Project Location: $(pwd)

🚀 QUICK COMMANDS
──────────────────────────────────────────────────────────────────
# Start Lima VM with GOST service (recommended)
cd lima && ./start-gost-service.sh

# Stop GOST service
cd lima && ./stop-gost-service.sh

# Run client manually (requires local gost binary)
cd client && ./start.sh

🔧 CONFIGURATION
──────────────────────────────────────────────────────────────────
Credentials:     client/.env (create from .env.example)
Server Config:   server/config.yaml
VM Config:       lima/lima-gost.yaml.template (auto-generated to lima-gost.yaml)

🧪 TESTING
──────────────────────────────────────────────────────────────────
# Test proxy connection
curl --socks5-hostname localhost:1080 https://ifconfig.me

# Test with verbose output
curl -v --socks5-hostname localhost:1080 https://ifconfig.me

# Check VM GOST version
limactl shell gost /usr/local/bin/gost -V

# Check Lima VM status
limactl list

# View GOST service logs in VM
limactl shell gost sudo journalctl -u gost.service -f

📦 INSTALL
──────────────────────────────────────────────────────────────────
# Automatic install in Lima VM
cd lima && ./start-gost-service.sh

# Run with Nix
nix run .#client

📚 DOCUMENTATION
──────────────────────────────────────────────────────────────────
README.md     - Main documentation and setup guide
QUICKREF.sh   - This quick reference
flake.nix     - Nix flake with package definitions

EOF
