{
  description = "A simple Rust project";

  inputs = {
    cargo2nix.url = "github:cargo2nix/cargo2nix";
    cargo2nix.inputs.flake-compat.follows = "flake-compat";
    cargo2nix.inputs.flake-utils.follows = "flake-utils";
    cargo2nix.inputs.nixpkgs.follows = "nixpkgs";
    cargo2nix.inputs.rust-overlay.follows = "rust-overlay";
    flake-compat.url = "github:edolstra/flake-compat";
    flake-compat.flake = false;
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "nixpkgs/nixos-21.11";
    nixpkgs-darwin.url = "nixpkgs/nixos-21.11-darwin";
    nixpkgs-master.url = "nixpkgs/master";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.flake-utils.follows = "flake-utils";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = inputs@{ self, flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachSystem [ "x86_64-darwin" "x86_64-linux" ] (system:
      let
        master = import inputs.nixpkgs-master { inherit system; };
        unstable = import inputs.nixpkgs-unstable { inherit system; };
        pkgs = import nixpkgs {
          inherit system;

          overlays = inputs.cargo2nix.overlays."${system}"
            ++ [ (final: prev: { inherit master unstable; }) ];
        };
        sharedInputs = with pkgs;
          [
            cargo-asm
            cargo-audit
            cargo-bloat
            cargo-cache
            cargo-deny
            cargo-edit
            cargo-expand
            cargo-flamegraph
            cargo-generate
            cargo-geiger
            cargo-make
            self.packages."${system}".cargo-outdated
            cargo-release
            cargo-sweep
            cargo-udeps
            cargo-watch
            cargo-whatfeatures
            clang
            just
            lld
            mdbook
          ] ++ (with self.packages."${system}"; [
            cargo2nix
            rust-analyzer
            sccache
          ]) ++ lib.optionals (stdenv.isLinux) [
            cargo-tarpaulin
            perf-tools
            strace
            valgrind
          ];

        rustChannel =
          pkgs.lib.removeSuffix "\n" (builtins.readFile ./rust-toolchain);

        rustTools = pkgs.rust-bin.stable.${rustChannel};

        # Uncomment if using cargo2nix after generating Cargo.nix
        # rustPkgs = pkgs.rustBuilder.makePackageSet' {
        #   inherit rustChannel;
        #   packageFun = import ./Cargo.nix;
        #   rootFeatures = [ "my_app/default" ];
        # };
      in {
        checks = {
          pre-commit-check = inputs.pre-commit-hooks.lib."${system}".run {
            src = ./.;
            hooks = {
              cargo-check.enable = true;
              clippy.enable = true;
              nix-linter.enable = true;
              nix-linter.excludes = [ "Cargo.nix" ];
              nixfmt.enable = true;
              prettier.enable = true;
              rustfmt.enable = true;
              shellcheck.enable = true;
            };
            tools = {
              inherit (rustTools) cargo rustFmt;
              inherit (pkgs.unstable) nodePackages;
              inherit (self.packages."${system}") clippy;
            };
          };
        };

        devShell = pkgs.mkShell {
          inherit (self.checks."${system}".pre-commit-check) shellHook;

          # Uncomment if using cargo2nix after generating Cargo.nix
          # inputsFrom = pkgs.lib.mapAttrsToList (_: pkg: pkg { })
          #   rustPkgs.noBuild.workspace;
          # nativeBuildInputs = [ rustPkgs.rustChannel ] ++ sharedInputs;
          nativeBuildInputs = [ rustTools.rust ];

          NIX_PATH =
            "nixpkgs=${nixpkgs}:unstable=${inputs.nixpkgs-unstable}:master=${inputs.nixpkgs-master}";
          # Uncomment if using gRPC/tonic
          # PROTOC = "${pkgs.protobuf}/bin/protoc";
          # PROTOC_INCLUDE = "${pkgs.protobuf}/include";
          # Uncomment to use sccache for caching intermediate crate artifacts
          # RUSTC_WRAPPER = "${self.packages."${system}".sccache}/bin/sccache";
          # Uncomment if using cargo2nix after generating Cargo.nix
          # RUST_SRC_PATH =
          #   "${rustPkgs.rustChannel}/lib/rustlib/src/rust/library";
          RUST_SRC_PATH = "${rustTools.rust}/lib/rustlib/src/rust/library";
        };

        packages = {
          inherit (pkgs.master) rust-analyzer sqlx-cli;
          inherit (pkgs.unstable) sccache;

          cargo2nix = inputs.cargo2nix.defaultPackage."${system}";

          cargo-outdated = pkgs.symlinkJoin {
            name = "cargo-outdated";
            paths = [ pkgs.cargo-outdated ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/cargo-outdated \
                --unset RUST_LOG
            '';
          };

          clippy = pkgs.symlinkJoin {
            name = "clippy";
            paths = [ pkgs.clang rustTools.clippy pkgs.lld ];
            buildInputs = [ pkgs.makeWrapper ];
            postBuild = ''
              wrapProgram $out/bin/cargo-clippy \
                --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.clang pkgs.lld ]}
            '';
          };

          # Uncomment to build Docker image without using a Docker daemon
          # docker = pkgs.dockerTools.streamLayeredImage {
          #   name = "my_app";
          #   tag = "latest";
          #   contents = with self.packages.x86_64-linux; [
          #     my_app_web
          #     my_app_cli
          #   ];
          #   config = {
          #     Cmd =
          #       [ "${self.packages.x86_64-linux.my_app_web}/bin/my_app_web" ];
          #     Env = [ "RUST_LOG=debug" ];
          #   };
          # };

          # my_app_cli = (rustPkgs.workspace.my_app_cli { }).bin;
          # my_app_web = (rustPkgs.workspace.my_app_web { }).bin;

          gcroot = pkgs.linkFarmFromDrvs "my_app"
            (with self.outputs; [ devShell."${system}".inputDerivation ]);

          nightlyDevShell = pkgs.mkShell {
            # Uncomment if using cargo2nix after generating Cargo.nix
            # inputsFrom = pkgs.lib.mapAttrsToList (_: pkg: pkg { })
            #   rustPkgs.noBuild.workspace;
            nativeBuildInputs = [ pkgs.rust-bin.nightly.latest.default ]
              ++ sharedInputs;
            RUSTFLAGS = "-Z macro-backtrace";
          };
        };
      });
}
