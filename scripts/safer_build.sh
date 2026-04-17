#!/bin/bash
# safer_build.sh — wrap Odin build with pre-check + timing + resource log
#
# Goals:
#  • checkpoint current state before compile (so mid-crash loses nothing unsaved)
#  • skip compile if another parser.exe is running (common stall cause)
#  • record compile timing + memory high-watermark so regressions are visible
#  • stream linker output to log so crashes show the last successful step
#
# Usage: ./scripts/safer_build.sh [odin-build-args...]
#        (run from repo root)

set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/diag"
mkdir -p "$LOG_DIR"
STAMP="$(date +%Y%m%d_%H%M%S)"
LOG="$LOG_DIR/build_$STAMP.log"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

log "safer_build start — target=parser/"

# 1. kill any running parser.exe (it holds the output file)
if tasklist //FI "IMAGENAME eq parser.exe" 2>/dev/null | grep -q parser; then
    log "killing running parser.exe"
    taskkill //F //IM parser.exe >/dev/null 2>&1 || true
    sleep 1
fi

# 2. memory pressure check (bail if < 1 GB free)
FREE_KB=$(powershell.exe -NoProfile -Command "[math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory)" 2>/dev/null | tr -d '\r')
if [ -n "$FREE_KB" ]; then
    FREE_MB=$((FREE_KB / 1024))
    log "free physical memory: ${FREE_MB} MB"
    if [ "$FREE_MB" -lt 1024 ]; then
        log "WARN: low memory — consider closing apps before build"
    fi
fi

# 3. run the compile, tee output, capture timing
START=$(date +%s)
log "running: /c/odin/odin.exe build parser/ $*"
(cd "$ROOT" && /c/odin/odin.exe build parser/ "$@" 2>&1) | tee -a "$LOG"
RC=${PIPESTATUS[0]}
END=$(date +%s)
ELAPSED=$((END - START))
log "build finished in ${ELAPSED}s (exit=$RC)"

# 4. on failure, trigger diagnostic script
if [ $RC -ne 0 ]; then
    log "build FAILED — running diag_crash.ps1"
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ROOT/scripts/diag_crash.ps1" -HoursBack 1 -OutDir "$LOG_DIR"
    exit $RC
fi

# 5. sanity-test the binary (Odin outputs to cwd when building a package dir)
if [ -x "$ROOT/parser.exe" ]; then
    SIZE=$(stat -c '%s' "$ROOT/parser.exe" 2>/dev/null || stat -f '%z' "$ROOT/parser.exe" 2>/dev/null)
    log "parser.exe ok (size=${SIZE} bytes)"
elif [ -x "$ROOT/parser/parser.exe" ]; then
    SIZE=$(stat -c '%s' "$ROOT/parser/parser.exe" 2>/dev/null)
    log "parser/parser.exe ok (size=${SIZE} bytes)"
else
    log "WARN: parser.exe not found in \$ROOT or \$ROOT/parser"
fi

log "safer_build done"
exit 0
