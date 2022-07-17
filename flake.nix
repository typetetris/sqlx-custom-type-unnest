{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  inputs.naersk.url = "github:nix-community/naersk/master";
  inputs.naersk.inputs.nixpkgs.follows = "nixpkgs";

  inputs.rust-analyzer-src.url = "github:rust-lang/rust-analyzer/release";
  inputs.rust-analyzer-src.flake = false;

  outputs = {
    self,
    nixpkgs,
    naersk,
    rust-analyzer-src,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    rust-src-filter = name: type: let
      result = (
        let
          baseName = baseNameOf (toString name);
        in
          baseName
          == "Cargo.toml"
          || baseName == "sqlx-data.json"
          || baseName == "Cargo.lock"
          || pkgs.lib.hasSuffix ".rs" baseName
          || pkgs.lib.hasSuffix ".jsonl" baseName
          || pkgs.lib.hasSuffix ".sql" baseName
          || type == "directory"
      );
    in
      result;
    naersk-lib = pkgs.callPackage naersk {};
    common-dev-packages = with pkgs; [
      sqlx-cli
      postgresql_14
      docker-compose
      openssl
      pkg-config
    ];
    defaultShellHook = ''
      export DATABASE_URL="postgresql://dev:dev@localhost/dev"
    '';
    recent-rust-analyzer = let
      rust-analyzer-rev = builtins.substring 0 7 (rust-analyzer-src.rev or "0000000");
      rust-analyzer-date = builtins.substring 0 8 (rust-analyzer-src.lastModifiedDate or "00000000");
      rust-analyzer-year = builtins.substring 0 4 rust-analyzer-date;
      rust-analyzer-month = builtins.substring 4 2 rust-analyzer-date;
      rust-analyzer-day = builtins.substring 6 2 rust-analyzer-date;
      rust-analyzer-version = "${rust-analyzer-year}-${rust-analyzer-month}-${rust-analyzer-day}";
    in
      pkgs.rustPlatform.buildRustPackage {
        pname = "rust-analyzer";
        version = rust-analyzer-version;
        src = rust-analyzer-src;

        cargoLock.lockFile = rust-analyzer-src + "/Cargo.lock";
        cargoBuildFlags = ["-p" "rust-analyzer"];
        doCheck = false;
        CARGO_INCREMENTAL = 0;
        RUST_ANALYZER_REV = rust-analyzer-rev;
        CFG_RELEASE = rust-analyzer-version;
        meta.mainProgram = "rust-analyzer";
      };
  in {
    packages.${system} = {
      default = naersk-lib.buildPackage {
        src = pkgs.lib.cleanSourceWith {
          filter = rust-src-filter;
          src = ./.;
        };
        nativeBuildInputs = [pkgs.pkg-config];
        buildInputs = [pkgs.openssl];
        SQLX_OFFLINE = "true";
      };
      rust-analyzer = recent-rust-analyzer;
    };

    devShells.${system} = {
      default = with pkgs;
        mkShell {
          buildInputs =
            common-dev-packages
            ++ [
              cargo
              cargo-edit
              cargo-watch
              rustc
              rustfmt
              pre-commit
              rustPackages.clippy
              recent-rust-analyzer
            ];
          RUST_SRC_PATH = rustPlatform.rustLibSrc;
          shellHook = defaultShellHook;
        };
    };
  };
}
