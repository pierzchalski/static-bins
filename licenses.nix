# Licence inventory for the Nix-built tools, read by ./notices.
#
# For each tool and target system: the tool's own derivation, every derivation
# reachable through buildInputs and propagatedBuildInputs (the libraries a
# static link can draw from), the C library and compiler runtime of its
# stdenv, and for Go tools the Go toolchain and the vendored module tree.
# This over-approximates what is linked; nativeBuildInputs (build-time tools)
# are left out.
#
# Output: one tab-separated line per (target, tool, component):
#   target tool kind name version licences homepage source-derivations
{
  lib,
  packages,
}: let
  targets = ["x86_64-linux" "aarch64-linux"];
  # Tool name as used in rebuild / the README -> flake package stem.
  tools = {
    bwrap = "bwrap";
    fuse-overlayfs = "fuse-overlayfs";
    passt = "passt";
    iptables = "iptables";
    iproute2 = "iproute2";
    nix = "nix";
    caddy = "caddy";
    sops = "sops";
    socat = "socat";
  };
  is-drv = x: builtins.isAttrs x && (x.type or null) == "derivation";
  library-inputs = d:
    builtins.filter is-drv (lib.flatten [(d.buildInputs or []) (d.propagatedBuildInputs or [])]);
  closure = root:
    map (item: item.drv) (builtins.genericClosure {
      startSet = [
        {
          key = root.drvPath;
          drv = root;
        }
      ];
      operator = item:
        map (d: {
          key = d.drvPath;
          drv = d;
        }) (library-inputs item.drv);
    });
  components = tool:
    lib.unique (
      closure tool
      ++ builtins.filter is-drv [
        (tool.stdenv.cc.libc or null)
        (tool.stdenv.cc.cc or null)
        (tool.go or null)
      ]
    );
  licence-ids = d: let
    raw = d.meta.license or [];
    list =
      if builtins.isList raw
      then raw
      else [raw];
    id = l:
      if builtins.isAttrs l
      then l.spdxId or l.shortName or l.fullName or "unknown"
      else builtins.toString l;
  in
    if list == []
    then "unknown"
    else lib.concatMapStringsSep " AND " id list;
  sources = d:
    builtins.filter is-drv (lib.flatten [(d.src or []) (d.srcs or [])]);
  clean = s: builtins.replaceStrings ["\t" "\n"] [" " " "] s;
  line = target: tool: d: kind:
    lib.concatStringsSep "\t" [
      target
      tool
      kind
      (clean (d.pname or (lib.getName d)))
      (clean (d.version or (lib.getVersion d)))
      (clean (licence-ids d))
      (clean (builtins.toString (d.meta.homepage or "")))
      (lib.concatMapStringsSep " " (s: s.drvPath) (sources d))
    ];
  tool-lines = target: tool: stem: let
    drv = packages."static-${stem}-${target}";
  in
    map (d: line target tool d "component") (components drv)
    # The vendored Go module tree is itself the source to search.
    ++ lib.optional (drv ? goModules) (lib.concatStringsSep "\t" [
      target
      tool
      "go-modules"
      "go-modules"
      (drv.version or "")
      "per module"
      ""
      drv.goModules.drvPath
    ]);
in
  lib.concatStringsSep "\n" (lib.flatten (map (target: lib.mapAttrsToList (tool-lines target) tools) targets)) + "\n"
