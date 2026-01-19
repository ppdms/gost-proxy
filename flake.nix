{
  description = "GOST v3 Proxy";

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
          default = pkgs.gost;
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
            gost
            lima
            curl
            openssl
            envsubst
          ];

          shellHook = ''
            echo "🚀 GOST Development Environment"
            echo ""
            echo "Available commands:"
            echo "  cd lima && ./start-gost-service.sh  - Start GOST client in Lima VM"
            echo "  cd lima && ./stop-gost-service.sh   - Stop GOST client"
            echo "  cd server && ./start.sh             - Start GOST server (Docker)"
          '';
        };
      }
    );
}
