{
  description = "GOST v3 Proxy with PHT protocol and Cloudflare Access support";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Build GOST with custom gost-x
        gost-custom = pkgs.buildGoModule rec {
          pname = "gost-custom";
          version = "3.2.6";

          src = pkgs.fetchFromGitHub {
            owner = "go-gost";
            repo = "gost";
            rev = "v${version}";
            hash = "sha256-REPLACE_WITH_ACTUAL_HASH"; # Run: nix-prefetch-url --unpack
          };

          vendorHash = "sha256-REPLACE_WITH_VENDOR_HASH"; # Run build once to get this

          # Replace gost-x with our custom fork
          overrideModAttrs = (
            _: {
              preBuild = ''
                # Clone custom gost-x fork with PHT header support
                git clone -b feature/pht-custom-headers https://github.com/ppdms/x.git /tmp/gost-x
                go mod edit -replace github.com/go-gost/x=/tmp/gost-x
                go mod tidy
              '';
            }
          );

          ldflags = [
            "-s"
            "-w"
            "-X main.version=${version}"
          ];

          meta = with pkgs.lib; {
            description = "GOST with custom PHT header support";
            homepage = "https://github.com/go-gost/gost";
            license = licenses.mit;
            maintainers = [ ];
          };
        };

        # Lima client scripts - run from current directory
        gost-client = pkgs.writeShellScriptBin "gost-client" ''
          set -e
          # Find project root by looking for flake.nix
          PROJECT_ROOT="$(pwd)"
          if [ ! -f "$PROJECT_ROOT/flake.nix" ]; then
            echo "Error: Must run from gost-proxy project root (where flake.nix is located)"
            echo "Current directory: $PROJECT_ROOT"
            exit 1
          fi
          cd "$PROJECT_ROOT/lima"
          exec ./start-gost-service.sh "$@"
        '';

        gost-client-stop = pkgs.writeShellScriptBin "gost-client-stop" ''
          set -e
          # Find project root by looking for flake.nix
          PROJECT_ROOT="$(pwd)"
          if [ ! -f "$PROJECT_ROOT/flake.nix" ]; then
            echo "Error: Must run from gost-proxy project root (where flake.nix is located)"
            echo "Current directory: $PROJECT_ROOT"
            exit 1
          fi
          cd "$PROJECT_ROOT/lima"
          exec ./stop-gost-service.sh "$@"
        '';

      in
      {
        packages = {
          default = gost-client;
          gost = gost-custom;
          client = gost-client;
          stop = gost-client-stop;
        };

        apps = {
          default = {
            type = "app";
            program = "${gost-client}/bin/gost-client";
          };

          client = {
            type = "app";
            program = "${gost-client}/bin/gost-client";
          };

          stop = {
            type = "app";
            program = "${gost-client-stop}/bin/gost-client-stop";
          };
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            go
            lima
            curl
            openssl
            envsubst
            gopls
            gotools
            go-tools
          ];

          shellHook = ''
            echo "🚀 GOST Development Environment"
            echo ""
            echo "Available commands:"
            echo "  cd lima && ./start-gost-service.sh  - Start GOST client in Lima VM"
            echo "  cd lima && ./stop-gost-service.sh   - Stop GOST client"
            echo "  cd server && ./start.sh             - Start GOST server (Docker)"
            echo ""
            echo "Configuration:"
            echo "  Client: ./client/config.yaml + ./client/.env"
            echo "  Server: ./server/config.yaml"
            echo ""
            echo "Documentation:"
            echo "  WORKING_CONFIG.md  - Complete setup guide"
            echo "  NIX_USAGE.md       - Nix integration guide"
            echo "  SETUP_COMPLETE.md  - Original setup notes"
          '';
        };
      }
    )
    // {
      # NixOS/nix-darwin module for system-level integration
      nixosModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          options.services.gost-client = {
            enable = lib.mkEnableOption "GOST client service";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.client;
              description = "GOST client package to use";
            };
          };

          config = lib.mkIf config.services.gost-client.enable {
            environment.systemPackages = [
              config.services.gost-client.package
              self.packages.${pkgs.system}.stop
            ];
          };
        };

      # Home Manager module
      homeManagerModules.default =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          options.programs.gost-client = {
            enable = lib.mkEnableOption "GOST client";

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.system}.client;
              description = "GOST client package to use";
            };
          };

          config = lib.mkIf config.programs.gost-client.enable {
            home.packages = [
              config.programs.gost-client.package
              self.packages.${pkgs.system}.stop
            ];
          };
        };
    };
}
