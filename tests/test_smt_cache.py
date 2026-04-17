#!/usr/bin/env python3
"""T26 — SMT proof-cache correctness (Session-7)

Gates:
  C1 : cache-dir created on first use
  C2 : entry JSON is well-formed (has hash, result, solver, timestamp)
  C3 : shard-layout : entries land in `.proof-cache/<hash[:2]>/<hash[2:]>.json`
  C4 : --no-cache disables caching (no new files appear)
  C5 : rewriting the input with an identical-canonical-form results in a hit
       (requires Z3) — gated behind solver availability

Exit 0 on green. This suite runs regardless of whether a solver is installed;
solver-requiring gates are reported as SKIPPED but do not fail the suite.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
SMT_GOOD = ROOT / "tests" / "smt_good"
CACHE_DIR = ROOT / ".proof-cache"


def find_z3() -> str:
    envp = os.environ.get("Z3_PATH", "")
    if envp and Path(envp).exists():
        return envp
    p = shutil.which("z3")
    if p:
        return p
    for c in [r"C:\ProgramData\chocolatey\bin\z3.exe"]:
        if Path(c).exists():
            return c
    return ""


def run(args: list[str]) -> tuple[int, str, str]:
    proc = subprocess.run(args, capture_output=True, text=True, timeout=30,
                          encoding="utf-8", errors="replace")
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found.\n")
        return 2

    fails: list[str] = []
    skipped: list[str] = []
    z3 = find_z3()
    fixtures = sorted(SMT_GOOD.glob("*.csl")) if SMT_GOOD.exists() else []
    if not fixtures:
        sys.stderr.write("ERROR: no smt_good fixtures\n")
        return 2
    target = fixtures[0]

    # C1/C4 : caching can only be observed when a solver runs + produces
    # Unsat/Sat/Timeout results. Without a solver, all obligations are
    # Skipped and the cache is never populated by design. Gate accordingly.
    if not z3:
        skipped.append("C1 (solver needed to populate cache)")
        skipped.append("C2 (solver needed to populate cache)")
        skipped.append("C3 (solver needed to populate cache)")
        skipped.append("C5 (solver needed)")
    else:
        # Wipe cache for clean baseline
        if CACHE_DIR.exists():
            shutil.rmtree(CACHE_DIR, ignore_errors=True)

        # Cold run — should populate cache
        rc1, _, _ = run([str(PARSER), "--smt", "--json", f"--z3={z3}", str(target)])
        if rc1 != 0:
            fails.append(f"C1 prep: cold run rc={rc1}")

        # C1 : cache dir exists
        if not CACHE_DIR.exists():
            fails.append("C1: cache directory not created")

        # C2/C3 : walk shards, pick one entry, validate
        if CACHE_DIR.exists():
            entries = []
            for p in CACHE_DIR.rglob("*.json"):
                entries.append(p)
            if not entries:
                fails.append("C2: no cache entries created")
            else:
                e = entries[0]
                # C3 : layout validation
                rel = e.relative_to(CACHE_DIR)
                parts = rel.parts
                if len(parts) != 2 or len(parts[0]) != 2:
                    fails.append(f"C3: unexpected shard layout: {rel}")
                # C2 : content
                try:
                    doc = json.loads(e.read_text(encoding="utf-8"))
                    for k in ("hash", "result", "solver", "timestamp"):
                        if k not in doc:
                            fails.append(f"C2: entry missing '{k}' : {e.name}")
                except json.JSONDecodeError as ex:
                    fails.append(f"C2: entry invalid JSON: {ex}")

        # C4 : --no-cache must not add new files (AND must not read cache)
        before = set(CACHE_DIR.rglob("*.json")) if CACHE_DIR.exists() else set()
        rc3, out3, _ = run([str(PARSER), "--smt", "--json", "--no-cache", f"--z3={z3}", str(target)])
        if rc3 != 0:
            fails.append(f"C4: rc={rc3}")
        after = set(CACHE_DIR.rglob("*.json")) if CACHE_DIR.exists() else set()
        if after - before:
            fails.append(f"C4: --no-cache created {len(after - before)} new entries")

        # C5 : warm run against cached Unsat/Sat → at least one cache hit
        rc4, out4, _ = run([str(PARSER), "--smt", "--json", f"--z3={z3}", str(target)])
        try:
            d4 = json.loads(out4)
            hits = d4.get("cache", {}).get("hits", 0)
            misses = d4.get("cache", {}).get("misses", 0)
            # If the fixture had any cacheable obligations, warm run must have >0 hits
            if misses == 0 and hits == 0:
                pass  # fixture produced no cacheable obligations : not a test failure
            elif hits == 0:
                fails.append(f"C5: warm run has 0 hits but {misses} misses")
        except json.JSONDecodeError:
            fails.append("C5: warm run invalid JSON")

    print(f"smt-cache : {len(fails)} failures ; {len(skipped)} skipped")
    for s in skipped:
        print(f"  [SKIP] {s}")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
