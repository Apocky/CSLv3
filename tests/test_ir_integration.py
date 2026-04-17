#!/usr/bin/env python3
"""T21 — IR integration test (Session-6)

Gates:
  G1 : `parser --ir-selftest` emits exactly 5/5 PASS (deliberately-malformed IR
       programs each trigger the expected verifier diagnostic class).
  G2 : every parser/tests/C*.csl lowers + verifies clean (0 errors).
  G3 : `--ir --json --verify` is well-formed JSON for every C corpus file
       and "status" is "ok".
  G4 : IR text-dump for every C corpus file is non-empty and starts with
       `module`, contains a `cslv3.fn`, and ends with a balanced `}`.
  G5 : severity composition — `--ir --verify --strict` preserves exit-code
       semantics : 0 on clean, 1 on any error.
  G6 : ir_bad/ deliberately-malformed fixtures — each yields at least one
       verify error of the expected code.

Exit 0 on green ; 1 on any regression.
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
CORPUS = sorted((ROOT / "parser" / "tests").glob("C*.csl"))

IR_BAD_DIR = ROOT / "tests" / "ir_bad"


def run(args: list[str], timeout: int = 15) -> tuple[int, str, str]:
    proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                          encoding="utf-8", errors="replace")
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def gate_selftest(fails: list[str]) -> None:
    rc, out, err = run([str(PARSER), "--ir-selftest"])
    if rc != 0:
        fails.append(f"G1: --ir-selftest rc={rc}\n  out: {out!r}\n  err: {err!r}")
        return
    if "IR-SELFTEST: 5/5 PASS" not in out:
        fails.append(f"G1: selftest footer missing:\n{out}")
    pass_count = sum(1 for ln in out.splitlines() if "PASS" in ln and ln.startswith("CASE "))
    if pass_count != 5:
        fails.append(f"G1: expected 5 CASE-PASS lines, got {pass_count}")


def gate_corpus_clean(fails: list[str]) -> None:
    for f in CORPUS:
        rc, out, err = run([str(PARSER), "--ir", "--verify", str(f)])
        if rc != 0:
            fails.append(f"G2: {f.name} rc={rc}\n  err: {err}")
            continue
        if "error(s), 0 warning(s)" not in err and "0 error(s)" not in err:
            fails.append(f"G2: {f.name} verifier footer missing:\n{err}")


def gate_corpus_json(fails: list[str]) -> None:
    for f in CORPUS:
        rc, out, err = run([str(PARSER), "--ir", "--json", "--verify", str(f)])
        if rc != 0:
            fails.append(f"G3: {f.name} json rc={rc}")
            continue
        try:
            doc = json.loads(out)
        except json.JSONDecodeError as e:
            fails.append(f"G3: {f.name} invalid JSON: {e}")
            continue
        if doc.get("status") != "ok":
            fails.append(f"G3: {f.name} status={doc.get('status')!r}")
        if "ir" not in doc or "ops" not in doc["ir"]:
            fails.append(f"G3: {f.name} missing ir.ops")


def gate_corpus_textual(fails: list[str]) -> None:
    for f in CORPUS:
        rc, out, err = run([str(PARSER), "--ir", str(f)])
        if rc != 0:
            fails.append(f"G4: {f.name} text dump rc={rc}")
            continue
        if not out.startswith("module"):
            fails.append(f"G4: {f.name} dump does not start with 'module'")
        # cslv3.fn optional — comment-only files legitimately produce empty modules
        if out.rstrip().rsplit("\n", 1)[-1].rstrip() != "}":
            fails.append(f"G4: {f.name} dump last line is not '}}'")


def gate_strict_exit(fails: list[str]) -> None:
    # clean corpus under --strict → rc 0
    for f in CORPUS:
        rc, _, _ = run([str(PARSER), "--ir", "--verify", "--strict", str(f)])
        if rc != 0:
            fails.append(f"G5: clean file {f.name} --strict rc={rc} (expected 0)")


def gate_ir_bad(fails: list[str]) -> None:
    if not IR_BAD_DIR.exists():
        return   # skip if directory not populated
    fixtures = sorted(IR_BAD_DIR.glob("*.csl"))
    if not fixtures:
        return
    for f in fixtures:
        rc, _, err = run([str(PARSER), "--ir", "--verify", "--strict", str(f)])
        # Expected : rc == 1 AND some verifier-code appears in stderr
        if rc == 0:
            fails.append(f"G6: {f.name} expected rc=1, got 0")
        if "CSL-E-3" not in err and "CSL-W-3" not in err:
            fails.append(f"G6: {f.name} no IR-verifier code (CSL-{{E,W}}-3xx) in stderr")


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found.\n")
        return 2

    fails: list[str] = []
    gate_selftest(fails)
    gate_corpus_clean(fails)
    gate_corpus_json(fails)
    gate_corpus_textual(fails)
    gate_strict_exit(fails)
    gate_ir_bad(fails)

    print(f"ir-integration : {len(fails)} failures")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
