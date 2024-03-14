{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
        pkgs = import nixpkgs {
          inherit system overlays;
        };
        lib = pkgs.lib;
        cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
        version = cargoToml.workspace.package.version;  
        # versionPatch = pkgs.writeText "version-patch.patch" ''
        #   diff --git a/crates/utils/src/version.rs b/crates/utils/src/version.rs
        #   new file mode 100644
        #   index 0000000..e69de29
        #   --- /dev/null
        #   +++ b/crates/utils/src/version.rs
        #   @@ -0,0 +1 @@
        #   +pub const VERSION: &str = "${version}";
        # '';

        # A *very* necessary OpenSSL wrapper
        openssl_wr = pkgs.symlinkJoin {
          name = "openssl-dev-out";
          paths = with pkgs; [ openssl.dev openssl.out ];
        };
      in
      with pkgs;
      {
          packages.default = pkgs.rustPlatform.buildRustPackage {
            inherit (cargoToml.package) name;
            pname = "lemmy_server";
            src = ./.;
            cargoLock.lockFile = ./Cargo.lock;

            # preConfigure = ''
            #   echo 'pub const VERSION: &str = "${version}";' > crates/utils/src/version.rs
            # '';

            buildInputs = [ postgresql pkg-config openssl.dev openssl libiconv protobuf ];

            nativeBuildInputs = [ pkg-config openssl.dev openssl rustfmt protobuf ];
            
            # Explicitly setting OpenSSL lib and include directories
            RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
            # Set OpenSSL environment variables
            OPENSSL_LIB_DIR = "${openssl_wr}/lib";
            OPENSSL_INCLUDE_DIR = "${openssl_wr}/include";
            OPENSSL_DIR = openssl_wr; # No .out needed because it's a symlinkJoin
            PROTOC = "${pkgs.protobuf}/bin/protoc";
            PROTOC_INCLUDE = "${pkgs.protobuf}/include";
            PKG_CONFIG_PATH = "${openssl_wr}/lib/pkgconfig:${pkgs.pkg-config}/lib/pkgconfig";
          };
        # Devshell (to be broken out to separate shell.nix later)      
        devShells.default = mkShell {
          name = "lemmy-shell";
          buildInputs = [ openssl openssl.dev postgresql libiconv protobuf pkg-config ];

          nativeBuildInputs = [ rustToolchain pkg-config rustfmt protobuf ];

          packages = [ rustToolchain cargo-deny cargo-edit cargo-watch rust-analyzer ];

          # Dev Environment variables
          RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";
          RUST_BACKTRACE = "1";
          # Dev Environment variables
          OPENSSL_LIB_DIR = "${openssl_wr}/lib";
          OPENSSL_INCLUDE_DIR = "${openssl_wr}/include";
          OPENSSL_DIR = openssl_wr;
          PROTOC = "${pkgs.protobuf}/bin/protoc";
          PROTOC_INCLUDE = "${pkgs.protobuf}/include";
          PKG_CONFIG_PATH = "${openssl_wr}/lib/pkgconfig:${pkgs.pkg-config}/lib/pkgconfig";

          # Environment variable to connect to the database
          LEMMY_DATABASE_URL = "postgres://lemmy:password@localhost:5432/lemmy";

          shellHook = ''
            echo "LEMMY_DATABASE_URL is set to $LEMMY_DATABASE_URL";
            # Any other setup steps can be added here
            nix eval --raw .
            echo 
            echo "evaluated successfully"
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