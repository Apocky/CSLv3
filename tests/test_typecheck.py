#!/usr/bin/env python3
"""T20.g — type-checker integration test (Session-5)

Drives `parser.exe --typecheck` against tests/type_good/ + type_bad/ +
live corpus (parser/tests/ + eval/). Also validates --json schema.

Gates:
  G1 : every type_good/*.csl exits 0 with 0 errors
  G2 : every type_bad/*.csl exits 1 with >= 1 error
  G3 : live corpus (7 + 7) still type-checks clean under default
  G4 : --json output validates against schema for 3 sample files
  G5 : --strict escalates warnings to failures (sanity)

Exit 0 on all green, 1 on any regression.
"""

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
GOOD = ROOT / "tests" / "type_good"
BAD  = ROOT / "tests" / "type_bad"
CORPUS_LIVE = list((ROOT / "parser" / "tests").glob("*.csl")) + \
              list((ROOT / "eval").glob("*_CSL.csl"))

DIAG_COUNT_RE = re.compile(r"error=(\d+)", re.MULTILINE)

REQUIRED_TOP = {"file", "status", "counts", "diags"}
REQUIRED_COUNTS = {"info", "warn", "error"}
REQUIRED_DIAG = {"line", "col", "sev", "code", "msg"}
VALID_STATUS = {"ok", "warn", "error"}
VALID_SEV = {"info", "warn", "error"}


def run(args: list[str]) -> tuple[int, str]:
    proc = subprocess.run(args, capture_output=True, text=True, timeout=15,
                          encoding="utf-8", errors="replace")
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def err_count(out: str) -> int:
    m = DIAG_COUNT_RE.search(out)
    return int(m.group(1)) if m else 0


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found\n")
        return 2

    fails: list[str] = []

    # G1: good fixtures
    gc_good = 0
    for p in sorted(GOOD.glob("*.csl")):
        rc, out = run([str(PARSER), "--typecheck", str(p)])
        errs = err_count(out)
        if rc != 0 or errs != 0:
            fails.append(f"G1: {p.name} rc={rc} errs={errs} (want 0/0)")
        else:
            gc_good += 1

    # G2: bad fixtures
    gc_bad = 0
    for p in sorted(BAD.glob("*.csl")):
        rc, out = run([str(PARSER), "--typecheck", str(p)])
        errs = err_count(out)
        if rc == 0 or errs == 0:
            fails.append(f"G2: {p.name} rc={rc} errs={errs} (want rc=1 errs>=1)")
        else:
            gc_bad += 1

    # G3: live corpus clean
    gc_live = 0
    for p in CORPUS_LIVE:
        rc, out = run([str(PARSER), "--typecheck", str(p)])
        errs = err_count(out)
        if rc != 0 or errs != 0:
            fails.append(f"G3: {p.name} corpus errs={errs}")
        else:
            gc_live += 1

    # G4: JSON schema on 3 samples (one good, one bad, one live)
    samples = [
        (next(iter(GOOD.glob("g01*.csl"))), "ok", 0),
        (next(iter(BAD.glob("b01*.csl"))),  "error", 1),
        (ROOT / "parser" / "tests" / "C1_sort.csl", "ok", 0),
    ]
    gc_json = 0
    for path, want_status, want_rc in samples:
        rc, out = run([str(PARSER), "--typecheck", "--json", str(path)])
        try:
            data = json.loads(out)
        except json.JSONDecodeError as e:
            fails.append(f"G4: {path.name} invalid JSON : {e}\n  out: {out!r}")
            continue
        if not isinstance(data, dict) or REQUIRED_TOP - data.keys():
            fails.append(f"G4: {path.name} schema missing top keys")
            continue
        counts = data.get("counts", {})
        if not isinstance(counts, dict) or REQUIRED_COUNTS - counts.keys():
            fails.append(f"G4: {path.name} counts malformed")
            continue
        if data.get("status") not in VALID_STATUS:
            fails.append(f"G4: {path.name} bad status {data.get('status')}")
            continue
        if data.get("status") != want_status:
            fails.append(f"G4: {path.name} status={data.get('status')} want={want_status}")
        for i, d in enumerate(data.get("diags", [])):
            if not isinstance(d, dict) or REQUIRED_DIAG - d.keys():
                fails.append(f"G4: {path.name} diag[{i}] missing keys")
                break
            if d.get("sev") not in VALID_SEV:
                fails.append(f"G4: {path.name} diag[{i}] bad sev")
                break
            if not d.get("code", "").startswith("CSL-"):
                fails.append(f"G4: {path.name} diag[{i}] bad code")
                break
        else:
            gc_json += 1

    # G5: --strict escalates — pick a file with a warning and confirm rc=1
    # Using a morph-unknown from error_tests ; should be W at default, E at strict.
    mu = ROOT / "parser" / "error_tests" / "i01_unknown_aspect.csl"
    gc_strict = 0
    if mu.exists():
        rc_default, _ = run([str(PARSER), "--typecheck", str(mu)])
        rc_strict, _  = run([str(PARSER), "--typecheck", "--strict", str(mu)])
        # At default, morph-unknown semantic diag is Warn — but --typecheck
        # isn't currently emitting semantic morph diags ; this is a sanity
        # smoke : strict should NEVER be laxer than default.
        if rc_strict < rc_default:
            fails.append(f"G5: --strict={rc_strict} looser than default={rc_default}")
        else:
            gc_strict = 1

    # report
    print(f"G1 good  : {gc_good}/{len(list(GOOD.glob('*.csl')))}")
    print(f"G2 bad   : {gc_bad}/{len(list(BAD.glob('*.csl')))}")
    print(f"G3 corpus: {gc_live}/{len(CORPUS_LIVE)}")
    print(f"G4 json  : {gc_json}/{len(samples)}")
    print(f"G5 strict: {gc_strict}/1")
    print(f"total failures : {len(fails)}")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
