# static-bins

Portable, statically linked Linux tools for `x86_64-linux` and
`aarch64-linux`, built by CI from pinned sources and published as GitHub
release assets.

| File in `bin/` | What | Built from |
| --- | --- | --- |
| `atuin` | [Atuin](https://atuin.sh) — shell history sync and search | upstream release, sha256-pinned |
| `bwrap` | [Bubblewrap](https://github.com/containers/bubblewrap) — unprivileged sandboxing | nixpkgs `pkgsStatic` |
| `caddy` | [Caddy](https://caddyserver.com) — HTTP server | nixpkgs `pkgsStatic` |
| `claude-code-proxy` | [pierzchalski/claude-code-proxy](https://github.com/pierzchalski/claude-code-proxy), a fork of [raine/claude-code-proxy](https://github.com/raine/claude-code-proxy) | pinned commit, Rust 1.91.1 musl |
| `dwarfs-universal` | [DwarFS](https://github.com/mhx/dwarfs) — compressed read-only filesystem (`dwarfs`, `dwarfsck`, `dwarfsextract`, `mkdwarfs` aliases) | upstream release, sha256-pinned |
| `fuse-overlayfs` | [fuse-overlayfs](https://github.com/containers/fuse-overlayfs) — FUSE overlayfs implementation | nixpkgs `pkgsStatic` |
| `ip`, `ss` | [iproute2](https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/) — Linux networking utilities | nixpkgs `pkgsStatic` |
| `nix-static` | [Nix](https://nixos.org/nix) — Nix package manager CLI | nixpkgs `pkgsStatic` (`nix.nix-cli`) |
| `pandoc` | [Pandoc](https://github.com/jgm/pandoc) — document converter | upstream release, sha256-pinned |
| `passt` | [passt](https://passt.top/passt/about/) — user-mode network connectivity (`pasta` alias) | nixpkgs `pkgsStatic` |
| `rclone` | [rclone](https://rclone.org) — cloud storage sync | upstream release, sha256-pinned |
| `socat` | [socat](http://www.dest-unreach.org/socat/) — bidirectional data relay | nixpkgs `pkgsStatic` |
| `sops` | [SOPS](https://getsops.io/) — secrets encryption | nixpkgs `pkgsStatic` |
| `xtables-nft-multi` | [iptables](https://www.netfilter.org/projects/iptables/index.html) — packet filtering (`iptables`, `iptables-save` aliases) | nixpkgs `pkgsStatic` |

Every file is checked to be a static ELF for its target (no interpreter, no
`NEEDED` entries). The MIT license in this repository covers the build
scripts only; each binary carries its upstream project's license, and
`BUILDINFO` records the exact source it was built from.

## Release assets

Each release (tag `vYYYY.MM.DD`) carries, per system:

- `<file>-<system>`: one asset per regular file in `bin/`, e.g.
  `claude-code-proxy-x86_64-linux`.
- `SHA256SUMS-<system>`: `sha256sum` manifest, paths written as `bin/<file>`.
- `BUILDINFO-<system>`: provenance. The repository commit, hashes of
  `flake.nix`, `flake.lock` and `rebuild`, one `pin.<tool>.*` line per source
  pin (release version and sha256, Rust source commit and `Cargo.lock` hash,
  or Nix output path), and one `alias.<name>=<target>` line per multicall
  alias.
- `static-bins-<system>.tar.gz`: `bin/` (aliases as relative symlinks, mode
  0755), `SHA256SUMS`, and `BUILDINFO`, for one-download installs.

## Installing (consumer contract)

Pin two things: a release tag, and your own copy of that release's
`SHA256SUMS-<system>` (review it once, commit it). Then fetch `install.sh`
from the same tag and run it:

```sh
tag=v2026.09.26
curl -fsSLo install.sh \
  "https://raw.githubusercontent.com/pierzchalski/static-bins/$tag/install.sh"
bash install.sh --tag "$tag" --sha256sums pinned/SHA256SUMS-x86_64-linux \
  --dest ~/.local/bin
```

`install.sh` downloads each file listed in the manifest, checks every hash
against it, and only then installs the files with mode 0755 and creates the
aliases. It installs nothing if any file fails. `--system` defaults to
`uname -m`; `--mode tarball` downloads the single tarball instead of one asset
per tool. To install a subset, delete lines from your pinned manifest. See
`install.sh --help` for all flags.

Aliases are not covered by the pinned manifest (they come from `BUILDINFO` or
the tarball's symlinks). `install.sh` only accepts an alias that is a plain
file name pointing at a verified file and that does not replace one.

To check a release by hand:

```sh
gh release download "$tag" --repo pierzchalski/static-bins \
  --pattern 'static-bins-x86_64-linux.tar.gz'
mkdir x && tar -xzf static-bins-x86_64-linux.tar.gz -C x
diff x/SHA256SUMS pinned/SHA256SUMS-x86_64-linux
(cd x && sha256sum --check --strict SHA256SUMS)
```

## Building locally

Requires Nix with flakes. Everything else, including both musl cross
toolchains, comes from `flake.nix`.

```sh
./rebuild --tool all --system x86_64-linux    # out/x86_64-linux/
./rebuild --tool all --system aarch64-linux   # cross-built on either host
./verify --system x86_64-linux                # runs smoke tests natively
./verify --system aarch64-linux --allow-cross # structural checks only
./rebuild --tool rclone --system x86_64-linux # update one tool in a complete bundle
./package --system x86_64-linux --out dist    # release assets
```

A one-tool rebuild first verifies that the existing bundle was built from the
same `flake.nix`, `flake.lock` and `rebuild`; after changing any of those,
rebuild `all`. `--partial` builds one tool into an otherwise empty bundle, for
smoke checks. Tuning knobs (`STATIC_BINS_MAX_JOBS`, `STATIC_BINS_CORES`,
`STATIC_BINS_ARTIFACT_JOBS`, `STATIC_BINS_HTTP_CONNECTIONS`) are described in
`./rebuild --help`.

## Adding or bumping a tool

- **Upstream release download** (rclone, pandoc, dwarfs, atuin): edit the
  `version` and both per-system `expected_sha256` values in the tool's
  `build_<tool>` function in `rebuild`. Get the hashes by downloading both
  archives and running `sha256sum`, and check them against upstream's
  published checksums where it has them.
- **claude-code-proxy**: tag the new commit in the fork
  (`eap/v<upstream>-<topic>`; never move a tag), then update `version`,
  `commit` and `lock_sha256` (the sha256 of its `Cargo.lock`) in
  `build_claude_code_proxy`.
- **Nix-built tools**: they follow `nixpkgs-unstable` in `flake.nix`. Change
  the pinned revision there and run `nix flake update nixpkgs-unstable`; this
  moves every Nix-built tool at once.
- **A new tool**: add it to `ALL_TOOLS`, `select_nix_packages` (if Nix-built)
  and a `build_<tool>` function in `rebuild`; to `REQUIRED_FILES`,
  `REQUIRED_PINS`, `REQUIRED_LINKS` and the smoke tests in `verify`; to the
  `nix_tool_pins` list in `rebuild` and a `static-<tool>-<system>` output in
  `flake.nix` if Nix-built; and to the table above.

Then run `./rebuild --tool all` for both systems and `./verify` before opening
a PR. Pull requests run a small smoke build (one Nix tool) in CI, not the
whole bundle.

## Cutting a release

Tag `main` with the date and push the tag:

```sh
git tag -a v2026.09.26 -m v2026.09.26 && git push origin v2026.09.26
```

The `release` workflow builds both systems on GitHub-hosted runners (aarch64 is
cross-compiled on x86_64), verifies them (runtime smoke tests for x86_64 on the
build runner and for aarch64 on an arm64 runner), and publishes the release
with the assets above. For a second release on the same day, append `.1`.
`workflow_dispatch` runs the same build and uploads the assets as workflow
artifacts without publishing a release.
