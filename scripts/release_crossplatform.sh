#!/usr/bin/env bash
# § Session-17 cross-platform release-bundle builder.
#
# Produces one dist/cslv3-<version>-<target>/ per target after running
# `odin build parser/` for that target triple. Bundles the same
# governance-doc set as release_v1.sh plus a per-target parser
# binary and (if present) cslv3-lsp.exe.
#
# Usage :
#   bash scripts/release_crossplatform.sh          # all available targets
#   bash scripts/release_crossplatform.sh linux    # linux only
#   bash scripts/release_crossplatform.sh macos    # macos only
#
# The Odin compiler's cross-compile support varies by host. This script
# attempts each target and skips cleanly on failure so the available
# targets still produce bundles. On a bare Windows host, windows-amd64
# will always succeed ; linux/macos require cross-compile toolchains
# (or running in WSL / on a Mac respectively). For the canonical
# release build, run this script on each target host and merge the
# resulting dist/ directories.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
DIST_DIR="$ROOT/dist"

# Accept : windows | linux | macos | all (default)
SELECTION="${1:-all}"

ODIN_BIN="${ODIN:-odin}"
if ! command -v "$ODIN_BIN" >/dev/null 2>&1; then
    if [[ -x "/c/Odin/odin.exe" ]]; then
        ODIN_BIN="/c/Odin/odin.exe"
    else
        echo "[fatal] odin compiler not on PATH ; set ODIN=/path/to/odin" >&2
        exit 2
    fi
fi

HOST_OS="unknown"
case "$(uname -s)" in
    Linux*)   HOST_OS="linux" ;;
    Darwin*)  HOST_OS="macos" ;;
    MINGW*|MSYS*|CYGWIN*) HOST_OS="windows" ;;
esac
echo "§ host OS : $HOST_OS  ;  Odin : $ODIN_BIN  ;  version : $VERSION"

# Build a target. Args : target-name odin-target-triple binary-suffix
build_target() {
    local tgt="$1"
    local triple="$2"
    local suffix="$3"

    local out="$ROOT/parser-$tgt$suffix"
    echo
    echo "§ build : $tgt  ($triple)"
    if ! "$ODIN_BIN" build "$ROOT/parser/" \
            -target:"$triple" \
            -out:"$out" \
            -o:speed 2>&1 | tail -5 ; then
        echo "  [skip] $tgt build failed (cross-compile toolchain missing?)"
        return 0
    fi
    if [[ ! -f "$out" ]]; then
        echo "  [skip] $tgt produced no output binary"
        return 0
    fi

    local bundle="$DIST_DIR/cslv3-$VERSION-$tgt"
    mkdir -p "$bundle"
    cp "$out" "$bundle/parser$suffix"
    if [[ -f "$ROOT/lsp/target/release/cslv3-lsp$suffix" ]]; then
        cp "$ROOT/lsp/target/release/cslv3-lsp$suffix" "$bundle/cslv3-lsp$suffix"
    elif [[ -f "$ROOT/lsp/target/release/cslv3-lsp.exe" && "$tgt" = "windows-x64" ]]; then
        cp "$ROOT/lsp/target/release/cslv3-lsp.exe" "$bundle/cslv3-lsp.exe"
    fi
    cp -r "$ROOT/specs"       "$bundle/specs"
    cp -r "$ROOT/parser/emit_schema" "$bundle/emit_schema"
    for gov in LICENSE README.md CHANGELOG.md STABILITY.md \
               MIGRATION_GUIDE.md SECURITY.md PRIME_DIRECTIVE.md VERSION ; do
        cp "$ROOT/$gov" "$bundle/" 2>/dev/null || true
    done
    # Per-target manifest.
    (cd "$bundle" && find . -type f | sort | while read -r f ; do
        # Use parser's own --sha256 if available for dogfood consistency.
        if [[ -x "$bundle/parser$suffix" && "$tgt" = "$HOST_OS-x64" ]]; then
            "$bundle/parser$suffix" --sha256 "$f" 2>/dev/null || \
                sha256sum "$f"
        else
            sha256sum "$f"
        fi
    done) > "$bundle.sha256"
    echo "  [ok] $bundle  +  $bundle.sha256"
    rm -f "$out"
}

mkdir -p "$DIST_DIR"

case "$SELECTION" in
    all|windows*)
        build_target "windows-x64" "windows_amd64" ".exe"
        ;;&
    all|linux*)
        build_target "linux-x64"   "linux_amd64"   ""
        ;;&
    all|macos*)
        build_target "macos-x64"   "darwin_amd64"  ""
        build_target "macos-arm64" "darwin_arm64"  ""
        ;;
    *)
        echo "[fatal] unknown selection : $SELECTION" >&2
        echo "        usage : $0 [all | windows | linux | macos]" >&2
        exit 2
        ;;
esac

echo
echo "§ dist/ contents :"
ls -1d "$DIST_DIR"/cslv3-"$VERSION"-* 2>/dev/null | while read -r b ; do
    echo "  $b"
done
echo "§ done."
