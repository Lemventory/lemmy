{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # lemmy-ui = {
    #   url = "git+https://github.com/LemInventory/lemmy-ui?submodules=1";
    #   # Make sure to handle this appropriately as it's not a flake.
    # };
  };
  outputs = { self, nixpkgs, rust-overlay, flake-utils, ... }:  
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [
          rust-overlay.overlays.default
          (final: prev: {
            rustToolchain = prev.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;
          })
        ];
        lib = pkgs.lib;
        cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
        version = cargoToml.workspace.package.version;
        pkgs = import nixpkgs {
          inherit system overlays;
        };
      in
      with pkgs;
      {
          packages.default = pkgs.rustPlatform.buildRustPackage {
            inherit (cargoToml.package) name;
            pname = "lemmy_server";
            src = ./.;
            cargoLock.lockFile = ./Cargo.lock;


            preConfigure = ''
              echo 'pub const VERSION: &str = "${version}";' > crates/utils/src/version.rs
            '';

            buildInputs = [ postgresql pkg-config openssl.dev openssl libiconv protobuf ];

            nativeBuildInputs = [ pkg-config openssl.dev openssl rustfmt protobuf ];
            
            # Explicitly setting OpenSSL lib and include directories
            OPENSSL_LIB_DIR = "${lib.getLib openssl.dev}/lib";
            OPENSSL_INCLUDE_DIR = "${openssl.dev}/include";
            OPENSSL_DIR = "${openssl.dev.out}";
            PROTOC = "${pkgs.protobuf}/bin/protoc";
            PROTOC_INCLUDE = "${pkgs.protobuf}/include";
            /* current issue with pkg config
            ``` OpenSSL libdir at `["/nix/store/xpz5n8nd9minrr31yw2d63xwg0941xb7-openssl-3.0.13-dev/lib"]` 
              does not contain the required files to either statically or dynamically link OpenSSL ```
              referenced here https://discourse.nixos.org/t/rust-openssl-woes/12340/2 
            */
            PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
          };
        # Devshell (to be broken out to separate shell.nix later)      
        devShells.default = mkShell {
          name = "lemmy-shell";
          buildInputs = [ openssl openssl.dev postgresql libiconv protobuf pkg-config ];

          nativeBuildInputs = [ rustToolchain pkg-config openssl openssl.dev rustfmt protobuf ];

          packages = [ rustToolchain cargo-deny cargo-edit cargo-watch rust-analyzer ];

          # Dev Environment variables
          RUST_BACKTRACE = "1";
          OPENSSL_LIB_DIR = "${lib.getLib openssl.dev}/lib"; # Note: This is directly accessible
          OPENSSL_INCLUDE_DIR = "${openssl.dev}/include";
          OPENSSL_DIR = "${openssl.dev.out}";
          PROTOC = "${pkgs.protobuf}/bin/protoc";
          PROTOC_INCLUDE = "${pkgs.protobuf}/include";
          PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
          HOST = "x86_64-unknown-linux-gnu";
          TARGET = "x86_64-unknown-linux-gnu";

          shellHook = ''
            export OPENSSL_LIB_DIR="${lib.getLib openssl.dev}/lib"
            export OPENSSL_INCLUDE_DIR="${openssl.dev}/include"
            export OPENSSL_DIR="${openssl.dev}/out"
            export PROTOC="${pkgs.protobuf}/bin/protoc"
            export PROTOC_INCLUDE="${pkgs.protobuf}/include"

            export RUST_BACKTRACE=1

            echo $OPENSSL_LIB_DIR 
            echo $OPENSSL_INCLUDE_DIR 
            echo $OPENSSL_DIR 
            echo $PROTOC 
            echo $PROTOC_INCLUDE 
            echo $PKG_CONFIG_PATH
            echo $HOST
            echo $TARGET
          '';
        };
      }
    );
  # unsing caches where applicable  
  nixConfig = {
    extra-experimental-features = ["nix-command flakes" "ca-derivations"];
    allow-import-from-derivation = "true";
    # This sets the flake to use nix cache.
    # Nix should ask for permission before using it,
    # but remove it here if you do not want it to.
    extra-substituters = [
      "https://cache.nixos.org"
      "https://cache.iog.io"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
  };
}       