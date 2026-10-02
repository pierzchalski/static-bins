#!/usr/bin/env bash

# Download a static-bins release, verify it against a caller-pinned manifest,
# and install it.

set -euo pipefail
export LC_ALL=C

usage() {
  cat <<'EOF_USAGE'
Usage: install.sh --tag TAG --sha256sums FILE --dest DIR [--system SYS]
                  [--mode assets|tarball] [--repo OWNER/NAME] [--base-url URL]

Downloads the tools listed in FILE from a static-bins GitHub release, checks
every file against FILE, and installs them into DIR with mode 0755, together
with their multicall aliases (pasta, iptables, mkdwarfs, ...).

FILE is the caller's pinned copy of the release's SHA256SUMS-<system> (lines of
"<sha256>  bin/<tool>"). It decides what is installed: remove lines to install
a subset. Nothing is installed unless every listed file matches.

Options:
  --tag TAG          Release tag, e.g. v2026.09.26.
  --sha256sums FILE  Pinned manifest to verify against.
  --dest DIR         Install directory; created if missing.
  --system SYS       x86_64-linux or aarch64-linux (default: from uname -m).
  --mode MODE        assets (default): one download per tool, aliases from
                     BUILDINFO-<system>. tarball: one download of
                     static-bins-<system>.tar.gz, aliases from its symlinks.
  --repo OWNER/NAME  GitHub repository (default: pierzchalski/static-bins).
  --base-url URL     Download from URL/<asset> instead of the GitHub release
                     (for mirrors and tests; file:// URLs work).
  -h, --help         Show this help.

Aliases are not covered by the manifest. They are accepted only as plain
names pointing at a verified file from the manifest, and never replace a
manifest file.

Requires bash, curl, sha256sum, tar, and gzip.
EOF_USAGE
}

die() {
  printf 'install.sh: %s\n' "$*" >&2
  exit 1
}

tag=
manifest=
dest=
system=
mode=assets
repo=pierzchalski/static-bins
base_url=
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --tag | --sha256sums | --dest | --system | --mode | --repo | --base-url)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      case "$1" in
        --tag) tag=$2 ;;
        --sha256sums) manifest=$2 ;;
        --dest) dest=$2 ;;
        --system) system=$2 ;;
        --mode) mode=$2 ;;
        --repo) repo=$2 ;;
        --base-url) base_url=$2 ;;
      esac
      shift 2
      ;;
    *)
      printf 'install.sh: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$tag" && -n "$manifest" && -n "$dest" ]] || {
  printf 'install.sh: --tag, --sha256sums, and --dest are required\n' >&2
  usage >&2
  exit 2
}
case "$mode" in
  assets | tarball) ;;
  *) die "--mode must be assets or tarball, not: $mode" ;;
esac
case "${system:-$(uname -m)}" in
  x86_64 | amd64 | x86_64-linux) system=x86_64-linux ;;
  aarch64 | arm64 | aarch64-linux) system=aarch64-linux ;;
  *) die "unsupported system: ${system:-$(uname -m)}" ;;
esac
[[ -f "$manifest" ]] || die "manifest not found: $manifest"
for command in curl sha256sum tar gzip install; do
  command -v "$command" >/dev/null 2>&1 || die "required command is missing: $command"
done
if [[ -z "$base_url" ]]; then
  base_url="https://github.com/$repo/releases/download/$tag"
fi

# A tool name is a plain file name: no slashes, no leading dot.
is_safe_name() {
  [[ "$1" =~ ^[A-Za-z0-9_+-][A-Za-z0-9._+-]*$ ]]
}

declare -A expected=()
declare -a names=()
while IFS= read -r line || [[ -n "$line" ]]; do
  [[ -n "$line" ]] || continue
  [[ "$line" =~ ^([0-9a-f]{64})\ \ bin/(.+)$ ]] || die "malformed manifest line: $line"
  hash=${BASH_REMATCH[1]}
  name=${BASH_REMATCH[2]}
  is_safe_name "$name" || die "unsafe name in manifest: $name"
  [[ -z "${expected[$name]:-}" ]] || die "duplicate manifest entry: $name"
  expected[$name]=$hash
  names+=("$name")
done <"$manifest"
[[ ${#names[@]} -gt 0 ]] || die "manifest lists no files: $manifest"

work="$(mktemp -d "${TMPDIR:-/tmp}/static-bins-install.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"

fetch() {
  local asset=$1 output=$2
  curl --fail --silent --show-error --location --retry 3 \
    --output "$output" "$base_url/$asset" || die "download failed: $base_url/$asset"
}

check_hash() {
  local name=$1 path=$2 actual
  actual="$(sha256sum -- "$path")"
  actual=${actual%% *}
  [[ "$actual" == "${expected[$name]}" ]] || die "sha256 mismatch for $name: got $actual, expected ${expected[$name]}"
}

declare -A aliases=()
add_alias() {
  local alias_name=$1 target=$2
  is_safe_name "$alias_name" || die "unsafe alias name: $alias_name"
  [[ -z "${expected[$alias_name]:-}" ]] || die "alias $alias_name would replace a verified file"
  # Skip aliases whose target the caller chose not to install.
  [[ -n "${expected[$target]:-}" ]] || return 0
  aliases[$alias_name]=$target
}

case "$mode" in
  assets)
    for name in "${names[@]}"; do
      fetch "$name-$system" "$work/bin/$name"
      check_hash "$name" "$work/bin/$name"
    done
    fetch "BUILDINFO-$system" "$work/BUILDINFO"
    while IFS= read -r line; do
      [[ "$line" =~ ^alias[.]([^=]+)=(.+)$ ]] || continue
      add_alias "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    done <"$work/BUILDINFO"
    ;;
  tarball)
    fetch "static-bins-$system.tar.gz" "$work/bundle.tar.gz"
    # Accept a flat bin/ directory, the two manifests, and the licence notices
    # beside them. Only bin/ is extracted, so no member can be written
    # through a symlink or outside the work directory.
    while IFS= read -r member; do
      [[ "$member" =~ ^(bin/|bin/[A-Za-z0-9_+-][A-Za-z0-9._+-]*|SHA256SUMS|BUILDINFO|THIRD_PARTY_NOTICES[.]md|licenses/.*)$ ]] \
        || die "unexpected tarball member: $member"
    done < <(tar -tzf "$work/bundle.tar.gz")
    mkdir "$work/extract"
    tar -xzf "$work/bundle.tar.gz" -C "$work/extract" --no-same-owner --no-same-permissions bin
    for name in "${names[@]}"; do
      path="$work/extract/bin/$name"
      [[ -f "$path" && ! -L "$path" ]] || die "tarball lacks regular file bin/$name"
      check_hash "$name" "$path"
      mv -- "$path" "$work/bin/$name"
    done
    while IFS= read -r alias_name; do
      add_alias "$alias_name" "$(readlink "$work/extract/bin/$alias_name")"
    done < <(find "$work/extract/bin" -mindepth 1 -maxdepth 1 -type l -printf '%f\n')
    ;;
esac

# Everything is verified; only now touch the destination.
mkdir -p -- "$dest"
for name in "${names[@]}"; do
  install -m 0755 -- "$work/bin/$name" "$dest/.$name.static-bins.$$"
  mv -f -- "$dest/.$name.static-bins.$$" "$dest/$name"
done
for alias_name in "${!aliases[@]}"; do
  ln -sfn -- "${aliases[$alias_name]}" "$dest/.$alias_name.static-bins.$$"
  mv -f -T -- "$dest/.$alias_name.static-bins.$$" "$dest/$alias_name"
done
printf 'install.sh: installed %d files and %d aliases from %s (%s) into %s\n' \
  "${#names[@]}" "${#aliases[@]}" "$tag" "$system" "$dest"
