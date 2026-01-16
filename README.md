# GOST Proxy with Cloudflare Access Support

This project provides a modified version of GOST v3 with support for custom HTTP headers in the PHT (Plain HTTP Tunnel) protocol. This enables using GOST behind Cloudflare Access or other header-based authentication systems.

The custom PHT header support is provided by [ppdms/x](https://github.com/ppdms/x) fork (branch: `feature/pht-custom-headers`), with an [upstream PR](https://github.com/go-gost/x/pull/80) pending.

## Features

- **Custom HTTP Headers**: Add authentication headers to PHT authorize, push, and pull requests
- **Cloudflare Access Integration**: Works seamlessly with Cloudflare Access Service Tokens
- **Lima VM Client**: macOS client runs in Ubuntu VM with systemd service
- **Nix Flake**: Full Nix integration for reproducible builds and system integration
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

### Without Nix

```bash
cd lima
./start-gost-service.sh
```

The script will automatically:
- Create and start Lima VM if needed
- Install Go and build dependencies
- Build GOST with custom PHT header support
- Set up and start the systemd service
- Configure port forwarding for SOCKS5 proxy on localhost:1080

## Project Structure

```
gost-proxy/
├── flake.nix             # Nix flake for reproducible builds
├── flake.lock            # Nix flake lock file
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

## Custom PHT Header Support

This project uses a custom fork of the GOST x library that adds header support to the PHT (Plain HTTP Tunnel) protocol:

**Fork:** [ppdms/x](https://github.com/ppdms/x) (branch: `feature/pht-custom-headers`)  
**Upstream PR:** https://github.com/go-gost/x/pull/80

Key modifications:
- Added `Header http.Header` field to PHT client
- Modified authorize, push, and pull requests to inject custom headers
- Added header parsing from YAML metadata configuration
- Fixed readLoop to continue polling instead of exiting when no data

These changes enable using GOST behind Cloudflare Access or other header-based authentication systems.

## Configuration

### Client Configuration (YAML)

```yaml
services:
  - name: local-socks5-proxy
    addr: :1080
    handler:
      type: socks5
      chain: cloudflare-chain
    listener:
      type: tcp

chains:
  - name: cloudflare-chain
    hops:
      - name: hop-0
        nodes:
          - name: cloudflare-pht
            addr: proxy.example.com:443
            connector:
              type: socks5
            dialer:
              type: phts
              tls:
                serverName: proxy.example.com
              metadata:
                authorizePath: /authorize
                pushPath: /push
                pullPath: /pull
                header:
                  CF-Access-Client-Id: "your-id.access"
                  CF-Access-Client-Secret: "your-secret"
```

## Building Custom GOST

### Automated (Lima VM)

The `lima/start-gost-service.sh` script automatically builds GOST with the custom fork:

```bash
cd lima
./start-gost-service.sh
```

This will:
1. Clone the custom [ppdms/x](https://github.com/ppdms/x) fork with PHT header support
2. Clone the main GOST repository
3. Replace the x dependency with the custom fork
4. Build the GOST binary
5. Install it in the VM

### Manual Build

To build manually:

```bash
# Clone repositories
git clone https://github.com/go-gost/gost.git
git clone -b feature/pht-custom-headers https://github.com/ppdms/x.git gost-x

# Build with custom fork
cd gost
go mod edit -replace github.com/go-gost/x=../gost-x
go mod tidy
go build -o gost ./cmd/gost
```

## Upstream Contribution

The PHT header support changes have been submitted upstream:  
**Pull Request:** https://github.com/go-gost/x/pull/80

Once merged, this custom fork will no longer be needed.

## Use Cases

- Access GOST servers behind Cloudflare Access
- Use header-based authentication with PHT protocol
- Deploy secure proxies with service token authentication
- Run as a system service for always-on connectivity

## License

This project follows the same license as GOST (MIT). See individual files for details.

## Credits

Based on [GOST v3](https://github.com/go-gost/gost) by @ginuerzh

