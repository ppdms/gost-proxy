# GOST Proxy with Cloudflare Access Support

This project provides a GOST v3 proxy setup optimized for working behind Cloudflare Access or other header-based authentication systems, specifically designed to bypass Zscaler and other corporate middleboxes using WebSocket Secure (WSS) protocol.

## Features

- **WSS Protocol**: Uses WebSockets over TLS to bypass buffering proxies (Zscaler)
- **Cloudflare Access Integration**: Authenticates using Service Tokens via HTTP headers
- **Lima VM Client**: macOS client runs in Ubuntu VM with systemd service for isolation
- **Nix Flake**: Reproducible environment and system integration
- **Zscaler Support**: Automatic CA extraction and installation for corporate proxies

## Quick Start

### With Nix (Recommended)

```bash
# Clone repository
git clone <repo-url> gost-proxy
cd gost-proxy

# Configure credentials
cd client
cp .env.example .env  # Create from template if needed
# Edit .env with your Cloudflare Access credentials

# Start client
nix run .#client

# Stop client
nix run .#stop
```

### Without Nix (macOS with Lima)

```bash
cd lima
./start-gost-service.sh
```

The script will automatically:
- Create and start Lima VM if needed
- Install standard GOST v3
- Set up and start the systemd service
- Configure port forwarding for SOCKS5 proxy on localhost:1080

## Project Structure

```
gost-proxy/
├── flake.nix             # Nix flake for reproducible builds
├── QUICKREF.sh           # Quick reference commands
├── README.md             # This file
├── client/               # Client configuration
│   ├── config.yaml       # GOST client config (uses env vars)
│   ├── .env              # Credentials (create from template)
│   └── start.sh          # Direct start script
├── server/               # Server configuration (Docker)
│   ├── config.yaml       # GOST server config
│   └── start.sh          # Docker start script
└── lima/                 # Lima VM client files (macOS)
    ├── lima-gost.yaml    # VM configuration
    ├── start-gost-service.sh  # Main service manager
    └── stop-gost-service.sh   # Service stopper
```

## Configuration

### Client Configuration (YAML)

```yaml
services:
  - name: local-socks5-proxy
    addr: :1080
    handler:
      type: socks5
      chain: cloudflare-chain

chains:
  - name: cloudflare-chain
    hops:
      - name: hop-0
        nodes:
          - name: cloudflare-wss
            addr: proxy.example.com:443
            connector:
              type: http
            dialer:
              type: wss
              tls:
                serverName: proxy.example.com
              metadata:
                header:
                  CF-Access-Client-Id: "your-id.access"
                  CF-Access-Client-Secret: "your-secret"
```

## Use Cases

- Access GOST servers behind Cloudflare Access
- Bypass corporate proxies that buffer HTTP chunks (Zscaler)
- Deploy secure proxies with service token authentication
- Run as a system service for always-on connectivity

## License

This project follows the same license as GOST (MIT). See individual files for details.

## Credits

Based on [GOST v3](https://github.com/go-gost/gost) by @ginuerzh

