{
  description = "ZTemplate development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [];
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Zig
            zig
            # Libraries
            libxml2
            pkg-config

            # For cross-compilation
            glibc
            glibc.dev
            
            gdb
            lldb
          ];

          shellHook = ''
          '';

          # Set environment variables to help find libraries
          PKG_CONFIG_PATH = "${pkgs.libxml2.dev}/lib/pkgconfig";
          
          # For cross-compilation
          ZIG_LIBC = "${pkgs.glibc}/lib";
        };
      }
    );
}
