{
  description = "ZTemplate development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [];
        };
        zigPkg = zig-overlay.packages.${system}.master;

        libcFile = pkgs.writeTextFile {
          name = "libc.txt";
          text = ''
            include_dir=${pkgs.glibc.dev}/include
            sys_include_dir=${pkgs.glibc.dev}/include
            crt_dir=${pkgs.glibc}/lib
            msvc_lib_dir=
            kernel32_lib_dir=
            gcc_dir=
          '';
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Zig
            zigPkg
            # Libraries
            pkg-config

            # For cross-compilation
            glibc
            glibc.dev
            
            gdb
            lldb
          ];

          shellHook = ''
            echo "Zig version: $(zig version)"
            export ZIG_LIBC_FILE="${libcFile}"
          '';

          # Set environment variables to help find libraries
          PKG_CONFIG_PATH = "${pkgs.libxml2.dev}/lib/pkgconfig";
        };
      }
    );
}
