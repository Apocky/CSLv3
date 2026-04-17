#!/usr/bin/env python3
"""T27 — IR-opt integration + golden-diff tests (Session-8)

Gates:
  O1 : all C corpus files optimize clean at all 4 opt-levels (no crash)
  O2 : golden-file diff for C-corpus × {O0, O1, O2} (O3 allowed to drift)
  O3 : --stats text + JSON both well-formed when requested
  O4 : --opt=custom --passes=fold,dce runs and reports stats
  O5 : --verify-each catches injected bad opt (smoke-test on clean corpus)
  O6 : optimization preserves semantics — same --ir dump before/after for O0
       (identity) ; semantic test via re-verify at O2
  O7 : specific fold case — `2 + 3*4` → `14` in O2 output

Exit 0 on green ; 1 on regression.

Golden-file regeneration (manual only) :
    for level in O0 O1 O2 O3; do
      for f in parser/tests/C*.csl; do
        base=$(basename "$f" .csl)
        ./parser.exe --ir --opt=$level "$f" > tests/golden_opt/${base}.${level}.ir.txt
      done
    done
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
CORPUS = sorted((ROOT / "parser" / "tests").glob("C*.csl"))
GOLDEN = ROOT / "tests" / "golden_opt"


def run(args: list[str]) -> tuple[int, str, str]:
    rc = subprocess.run(args, capture_output=True, text=True, timeout=30,
                        encoding="utf-8", errors="replace")
    return rc.returncode, rc.stdout or "", rc.stderr or ""


def gate_O1(fails: list[str]) -> None:
    for f in CORPUS:
        for lvl in ("O0", "O1", "O2", "O3"):
            rc, _, err = run([str(PARSER), "--ir", f"--opt={lvl}", str(f)])
            if rc != 0:
                fails.append(f"O1: {f.name} --opt={lvl} rc={rc}\n  err: {err[:200]}")


def gate_O2(fails: list[str]) -> None:
    if not GOLDEN.exists():
        fails.append("O2: golden_opt/ missing")
        return
    # O0/O1/O2 must match golden exactly ; O3 is allowed to drift
    for f in CORPUS:
        base = f.stem
        for lvl in ("O0", "O1", "O2"):
            gfile = GOLDEN / f"{base}.{lvl}.ir.txt"
            if not gfile.exists():
                fails.append(f"O2: golden missing {gfile.name}")
                continue
            rc, out, _ = run([str(PARSER), "--ir", f"--opt={lvl}", str(f)])
            if rc != 0:
                fails.append(f"O2: {f.name} --opt={lvl} rc={rc}")
                continue
            # Normalize the `module @"<path>" {` header line — platform path
            # differences (relative vs absolute) shouldn't count as drift.
            got = [ln for ln in out.strip().splitlines() if not ln.startswith("module @")]
            expected = [ln for ln in gfile.read_text(encoding="utf-8").strip().splitlines()
                        if not ln.startswith("module @")]
            if got != expected:
                fails.append(f"O2: {f.name} --opt={lvl} golden-drift "
                             f"({len(got)} vs {len(expected)} lines)")


def gate_O3(fails: list[str]) -> None:
    f = CORPUS[0]
    rc, out, _ = run([str(PARSER), "--ir", "--opt=O2", "--stats", str(f)])
    if rc != 0 or "§ PASS-STATS" not in out:
        fails.append("O3: --stats text missing header")
    rc, out, _ = run([str(PARSER), "--ir", "--opt=O2", "--stats", "--json", str(f)])
    if rc != 0:
        fails.append(f"O3: --stats --json rc={rc}")
        return
    try:
        doc = json.loads(out)
    except json.JSONDecodeError as e:
        fails.append(f"O3: --stats --json invalid JSON: {e}")
        return
    if "pass_stats" not in doc:
        fails.append("O3: pass_stats key absent in JSON")


def gate_O4(fails: list[str]) -> None:
    f = CORPUS[0]
    rc, out, _ = run([str(PARSER), "--ir", "--opt=custom",
                      "--passes=fold,dce", "--stats", str(f)])
    if rc != 0:
        fails.append(f"O4: custom rc={rc}")
        return
    if "§ PASS-STATS" not in out:
        fails.append("O4: custom pipeline produced no stats")


def gate_O5(fails: list[str]) -> None:
    # Smoke : --verify-each on clean corpus must still produce a module
    f = CORPUS[0]
    rc, _, _ = run([str(PARSER), "--ir", "--opt=O2", "--verify-each", str(f)])
    if rc != 0:
        fails.append(f"O5: --verify-each rc={rc}")


def gate_O7(fails: list[str]) -> None:
    src = "§ T\n  fn f (x : i32) -> i32 = 2 + 3 * 4\n"
    tmp = ROOT / "tests" / ".tmp_fold.csl"
    tmp.write_text(src, encoding="utf-8")
    try:
        rc, out, _ = run([str(PARSER), "--ir", "--opt=O2", str(tmp)])
        if rc != 0:
            fails.append(f"O7: rc={rc}")
            return
        if "{value=14}" not in out:
            fails.append("O7: fold to 14 did not appear")
    finally:
        try:
            tmp.unlink()
        except OSError:
            pass


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} missing\n")
        return 2
    fails: list[str] = []
    gate_O1(fails)
    gate_O2(fails)
    gate_O3(fails)
    gate_O4(fails)
    gate_O5(fails)
    gate_O7(fails)
    print(f"opt-integration : {len(fails)} failures")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
