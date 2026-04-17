#!/usr/bin/env python3
"""T26.3 — SMT solver version-pin check (Session-8)

Verifies that installed Z3 + CVC5 meet CSLv3 minimum-version requirements.
Pins per DECISIONS.md T26.3 entry:

  Z3   : >= 4.13  (released 2024-Q3)  ← chosen ∵ stable QF_UFLIA + SMT-LIB2-v2.6
  CVC5 : >= 1.1   (released 2024-Q2)  ← chosen ∵ Alethe proof output + Unicode

Emits both text + JSON. Exits nonzero on mismatch for CI gating.
"""

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

PINS = {
    "z3":   (4, 13, 0),
    "cvc5": (1, 1,  0),
}


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


def z3_version(path: str) -> tuple[int, int, int] | None:
    try:
        out = subprocess.check_output([path, "-version"], text=True, timeout=10)
    except Exception:
        return None
    # "Z3 version 4.16.0 - 64 bit"
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", out)
    return (int(m[1]), int(m[2]), int(m[3])) if m else None


def cvc5_version(path: str) -> tuple[int, int, int] | None:
    try:
        out = subprocess.check_output([path, "--version"], text=True, timeout=10)
    except Exception:
        return None
    # "This is cvc5 version 1.3.3 [git ...]"
    m = re.search(r"version\s+(\d+)\.(\d+)\.(\d+)", out)
    return (int(m[1]), int(m[2]), int(m[3])) if m else None


def ge(a: tuple[int, int, int], b: tuple[int, int, int]) -> bool:
    return a >= b


def main() -> int:
    want_json = "--json" in sys.argv
    report = {"solvers": []}
    any_mismatch = False

    for name, pin in PINS.items():
        path = find_solver(name)
        if not path:
            report["solvers"].append({
                "name": name, "found": False, "path": "",
                "version": None, "pin": list(pin), "ok": False,
                "reason": "not-installed",
            })
            any_mismatch = True
            continue

        ver = z3_version(path) if name == "z3" else cvc5_version(path)
        if ver is None:
            report["solvers"].append({
                "name": name, "found": True, "path": path,
                "version": None, "pin": list(pin), "ok": False,
                "reason": "version-parse-failed",
            })
            any_mismatch = True
            continue

        ok = ge(ver, pin)
        if not ok:
            any_mismatch = True
        report["solvers"].append({
            "name": name, "found": True, "path": path,
            "version": list(ver), "pin": list(pin), "ok": ok,
            "reason": "" if ok else "below-pinned-minimum",
        })

    if want_json:
        print(json.dumps(report, indent=2))
    else:
        print("§ SMT-SOLVER VERSION CHECK")
        for s in report["solvers"]:
            v_s = f"{s['version'][0]}.{s['version'][1]}.{s['version'][2]}" if s["version"] else "?"
            p_s = f"{s['pin'][0]}.{s['pin'][1]}.{s['pin'][2]}"
            status = "OK" if s["ok"] else "FAIL"
            extra = f" ({s['reason']})" if s["reason"] else ""
            print(f"  {s['name']}: installed={v_s} pinned>={p_s} [{status}]{extra}")
            if s["path"]:
                print(f"    path: {s['path']}")

    return 1 if any_mismatch else 0


if __name__ == "__main__":
    sys.exit(main())
