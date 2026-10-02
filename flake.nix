{
  description = "Pinned toolchains and packages for the static-bins release bundle.";

  inputs = {
    # Supplies rust-overlay's package set (the claude-code-proxy Rust toolchain).
    nixpkgs.url = "github:nixos/nixpkgs?ref=25.05";

    # Source of every Nix-built static tool, both musl cross toolchains, and the
    # build utilities. Keep this revision explicit so x86_64 and aarch64 builds
    # cannot drift with the caller's Nix registry.
    nixpkgs-unstable.url = "github:nixos/nixpkgs/aff8a0b28396750446e5537a96461bc4facdb287";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    nixpkgs,
    nixpkgs-unstable,
    rust-overlay,
    ...
  }: let
    # Build hosts. Either host can build both targets.
    host-systems = ["x86_64-linux" "aarch64-linux"];
    for-each-host = f: nixpkgs.lib.genAttrs host-systems f;
    host-packages = system: let
      pkgs = import nixpkgs {
        inherit system;
        overlays = [(import rust-overlay)];
      };
      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
      };
      static-targets = {
        x86_64-linux = pkgs-unstable.pkgsCross.musl64;
        aarch64-linux = pkgs-unstable.pkgsCross.aarch64-multiplatform-musl;
      };
      mk-static-packages = target-system: target-pkgs: let
        base-static-pkgs = target-pkgs.pkgsStatic;
        # Native musl enables libcap-ng's file_caps_test, which defines the
        # same xattr stubs musl 1.2.6 now provides and fails to link. Cross
        # package sets already disable tests; avoid perturbing their hashes
        # with a redundant override so Hydra-cached inputs remain reusable.
        static-pkgs =
          if (base-static-pkgs.libcap_ng.doCheck or false)
          then
            base-static-pkgs.extend (_final: previous: {
              libcap_ng = previous.libcap_ng.overrideAttrs (_: {
                doCheck = false;
              });
            })
          else base-static-pkgs;
      in {
        "static-bwrap-${target-system}" = static-pkgs.bubblewrap;
        "static-fuse-overlayfs-${target-system}" = static-pkgs.fuse-overlayfs;
        "static-passt-${target-system}" = static-pkgs.passt;
        "static-iptables-${target-system}" = static-pkgs.iptables;
        "static-iproute2-${target-system}" = static-pkgs.iproute2;
        # The full `nix` package is nix-everything: it links this exact CLI
        # component into a larger output and additionally builds manuals,
        # legacy programs, and their test gates. Only bin/nix is shipped, so
        # selecting its source component avoids that unrelated build graph.
        "static-nix-${target-system}" = static-pkgs.nix.nix-cli;
        "static-caddy-${target-system}" = static-pkgs.caddy.overrideAttrs (_: {
          doCheck = false;
        });
        "static-sops-${target-system}" = static-pkgs.sops;
        "static-socat-${target-system}" = static-pkgs.socat;
      };
    in
      (mk-static-packages "x86_64-linux" static-targets.x86_64-linux)
      // (mk-static-packages "aarch64-linux" static-targets.aarch64-linux)
      // {
        static-rust-toolchain = pkgs.rust-bin.stable."1.91.1".minimal.override {
          targets = [
            "x86_64-unknown-linux-musl"
            "aarch64-unknown-linux-musl"
          ];
        };
        static-build-tools = pkgs-unstable.buildEnv {
          name = "static-bins-build-tools";
          paths = with pkgs-unstable; [
            binutils
            coreutils
            curl
            file
            findutils
            gawk
            gitMinimal
            gnugrep
            gnused
            gnutar
            gzip
            unzip
          ];
        };
        static-cc-x86_64-linux = static-targets.x86_64-linux.stdenv.cc;
        static-cc-aarch64-linux = static-targets.aarch64-linux.stdenv.cc;
        static-binutils-x86_64-linux = static-targets.x86_64-linux.stdenv.cc.bintools;
        static-binutils-aarch64-linux = static-targets.aarch64-linux.stdenv.cc.bintools;
      };
  in {
    packages = for-each-host host-packages;
    formatter = for-each-host (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
