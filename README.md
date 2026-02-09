# GOST Proxy with Cloudflare Access Support

This project provides a GOST v3 proxy setup optimized for working behind Cloudflare Access or other header-based authentication systems, specifically designed to bypass Zscaler and other corporate middleboxes using WebSocket Secure (WSS) protocol.

## Features

- **WSS Protocol**: Uses WebSockets over TLS to bypass buffering proxies (Zscaler)
- **Cloudflare Access Integration**: Authenticates using Service Tokens via HTTP headers
- **Multiple Servers**: Connect to N different GOST servers simultaneously, each with its own credentials
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
- Detect configured servers from .env
- Generate Lima VM config with required port forwards
- Create and start Lima VM if needed
- Install standard GOST v3
- Set up and start the systemd service

## Project Structure

```
gost-proxy/
├── flake.nix             # Nix flake for reproducible builds
├── QUICKREF.sh           # Quick reference commands
├── README.md             # This file
├── client/               # Client configuration
│   ├── .env.example      # Environment template
│   ├── .env              # Credentials (create from template)
│   └── start.sh          # Client start script
├── server/               # Server configuration (Docker)
│   ├── config.yaml       # GOST server config
│   └── start.sh          # Docker start script
└── lima/                 # Lima VM client files (macOS)
    ├── lima-gost.yaml.template  # VM configuration template
    ├── lima-gost.yaml    # Generated VM config (auto-created)
    ├── start-gost-service.sh  # Main service manager
    └── stop-gost-service.sh   # Service stopper
```

## Configuration

### Configuration

The client supports connecting to multiple GOST servers simultaneously. Each server gets its own:
- Cloudflare Access credentials
- Server address
- Local SOCKS5 port

Configure in `.env`:

```bash
# Server 1
SERVER1_CF_CLIENT_ID=xxxxx.access
SERVER1_CF_CLIENT_SECRET=xxxxx
SERVER1_ADDRESS=proxy1.example.com:443
SERVER1_LOCAL_PORT=1081

# Server 2
SERVER2_CF_CLIENT_ID=yyyyy.access
SERVER2_CF_CLIENT_SECRET=yyyyy
SERVER2_ADDRESS=proxy2.example.com:443
SERVER2_LOCAL_PORT=1082

# Add more as needed (SERVER3_, SERVER4_, ...)
```

### Example Client Configuration (YAML)

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

