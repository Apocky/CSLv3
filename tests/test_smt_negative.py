#!/usr/bin/env python3
"""T26.2 — SMT negative-fixture tests (Session-8)

Validates that smt_bad/ fixtures produce Sat counter-examples under both
Z3 and CVC5, and that --strict exits 1 in every case.

Gates:
  N1 : 15/15 smt_bad/*.csl report failure-count > 0 under Z3
  N2 : 15/15 smt_bad/*.csl report failure-count > 0 under CVC5
  N3 : --strict returns rc=1 for every fixture
  N4 : JSON output contains at least one obligation with ok=false

Solver availability required — test reports SKIPPED when unavailable.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
SMT_BAD = ROOT / "tests" / "smt_bad"


def find_solver(name: str) -> str:
    env = os.environ.get(f"{name.upper()}_PATH", "")
    if env and Path(env).exists():
        return env
    p = shutil.which(name)
    if p:
        return p
    for c in [Path(f"C:/Users/Apocky/AppData/Local/{name}")]:
        if c.exists():
            for exe in c.rglob(f"{name}.exe"):
                return str(exe)
    return ""


def run(args: list[str], timeout: int = 30) -> tuple[int, str]:
    rc = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                        encoding="utf-8", errors="replace")
    return rc.returncode, rc.stdout + rc.stderr


def run_json(args: list[str]) -> tuple[int, dict]:
    rc, out = run(args)
    try:
        doc = json.loads(out)
    except json.JSONDecodeError:
        doc = {}
    return rc, doc


def gate_per_solver(name: str, path: str, fails: list[str]) -> None:
    fixtures = sorted(SMT_BAD.glob("*.csl"))
    for f in fixtures:
        # N3 : --strict must rc=1
        rc, _ = run([str(PARSER), "--smt", "--strict", f"--{name}={path}",
                     f"--solver={name}", str(f)])
        if rc == 0:
            fails.append(f"[{name}] N3: {f.name} --strict rc=0 (expected 1)")

        # N1/N2/N4 : JSON inspection
        rc, doc = run_json([str(PARSER), "--smt", "--json", f"--{name}={path}",
                            f"--solver={name}", str(f)])
        counts = doc.get("counts", {})
        if counts.get("failure", 0) == 0:
            fails.append(f"[{name}] N1/N2: {f.name} failure-count=0")
        obs = doc.get("obligations", [])
        if not any(not o.get("ok", True) for o in obs):
            fails.append(f"[{name}] N4: {f.name} no ok=false obligation")


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} missing\n")
        return 2
    fixtures = sorted(SMT_BAD.glob("*.csl"))
    if len(fixtures) != 15:
        sys.stderr.write(f"ERROR: expected 15 smt_bad fixtures, found {len(fixtures)}\n")
        return 2

    z3 = find_solver("z3")
    cvc5 = find_solver("cvc5")

    fails: list[str] = []
    skipped: list[str] = []
    if z3:
        gate_per_solver("z3", z3, fails)
    else:
        skipped.append("N1/N3/N4 for Z3")
    if cvc5:
        gate_per_solver("cvc5", cvc5, fails)
    else:
        skipped.append("N2/N3/N4 for CVC5")

    print(f"smt-negative : {len(fails)} failures ; {len(skipped)} skipped")
    print(f"  fixtures: {len(fixtures)}")
    print(f"  z3   : {z3 or '<not available>'}")
    print(f"  cvc5 : {cvc5 or '<not available>'}")
    for s in skipped:
        print(f"  [SKIP] {s}")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
