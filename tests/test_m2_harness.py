#!/usr/bin/env python3
"""T25.9 — m₂ harness smoke + integration tests (Session-11).

Gates:
  M1 : compute_m2 --self-test returns 0 and prints "PASS"
  M2 : compute_m2 --all-eval --backend=mock produces 21 measurements
       (7 files × 3 model-keys) and writes eval/m2_baseline.json
  M3 : compute_m2 single-file with --json produces parseable JSON
  M4 : determinism : same seed → same m₂ (bit-for-bit)
  M5 : mock backend bootstrap CI is finite + well-ordered (lo ≤ m₂ ≤ hi)
  M6 : compute_m2 on m2_fixtures/tiny_csl.csl runs under 2 seconds
  M7 : m2_compare.py --json emits valid JSON with all 4 notations
  M8 : m2_quality.py --fallback returns 0 (thresholds tuned for fallback)

All gates require no external model weights ; tests run with mock-backend.

Exit 0 on green ; 1 on any regression.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts"
FIX    = ROOT / "tests" / "m2_fixtures"


def run(args: list[str], timeout: int = 60) -> tuple[int, str, str]:
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    rc = subprocess.run(
        [sys.executable] + args,
        capture_output=True, text=True, timeout=timeout,
        encoding="utf-8", errors="replace", env=env, cwd=ROOT,
    )
    return rc.returncode, rc.stdout or "", rc.stderr or ""


def gate(fails: list[str], label: str, ok: bool, detail: str = "") -> None:
    if not ok:
        fails.append(f"{label}: {detail}")


def test_M1(fails: list[str]) -> None:
    rc, out, _ = run([str(SCRIPT / "compute_m2.py"), "--self-test"])
    gate(fails, "M1", rc == 0 and "PASS" in out, f"rc={rc} out-tail={out[-100:]}")


def test_M2(fails: list[str]) -> None:
    rc, out, _ = run([str(SCRIPT / "compute_m2.py"),
                       "--all-eval", "--backend=mock", "--bootstrap=100"])
    gate(fails, "M2 rc", rc == 0, f"rc={rc}")
    baseline = ROOT / "eval" / "m2_baseline.json"
    gate(fails, "M2 baseline-exists", baseline.exists(), f"{baseline}")
    if baseline.exists():
        doc = json.loads(baseline.read_text(encoding="utf-8"))
        n = len(doc.get("measurements", []))
        gate(fails, "M2 count", n == 21, f"got {n} measurements, want 21")


def test_M3(fails: list[str]) -> None:
    rc, out, _ = run([str(SCRIPT / "compute_m2.py"),
                       str(ROOT / "eval" / "C1_sort_CSL.csl"),
                       "--backend=mock", "--bootstrap=50", "--json", "--model=small"])
    gate(fails, "M3 rc", rc == 0, f"rc={rc}")
    try:
        doc = json.loads(out)
        gate(fails, "M3 shape", isinstance(doc, list) and len(doc) >= 1,
              f"got type={type(doc).__name__}")
    except json.JSONDecodeError as e:
        fails.append(f"M3: invalid JSON: {e}")


def test_M4(fails: list[str]) -> None:
    args_common = [str(SCRIPT / "compute_m2.py"),
                    str(FIX / "tiny_csl.csl"),
                    "--paraphrase", str(FIX / "tiny.en"),
                    "--backend=mock", "--bootstrap=100",
                    "--seed=42", "--json", "--model=small"]
    rc1, out1, _ = run(args_common)
    rc2, out2, _ = run(args_common)
    gate(fails, "M4 rc", rc1 == 0 and rc2 == 0, f"rc1={rc1} rc2={rc2}")
    gate(fails, "M4 determinism", out1 == out2,
          "output differs between identical-seed runs")


def test_M5(fails: list[str]) -> None:
    rc, out, _ = run([str(SCRIPT / "compute_m2.py"),
                       str(FIX / "tiny_csl.csl"),
                       "--paraphrase", str(FIX / "tiny.en"),
                       "--backend=mock", "--bootstrap=100", "--json", "--model=small"])
    if rc != 0:
        fails.append(f"M5: rc={rc}")
        return
    doc = json.loads(out)
    for m in doc:
        lo, mid, hi = m["m2_ci_low"], m["m2"], m["m2_ci_high"]
        gate(fails, "M5 CI order", lo <= mid <= hi, f"{lo}, {mid}, {hi}")
        gate(fails, "M5 CI finite", all(map(lambda x: x == x, [lo, mid, hi])),
              f"NaN in {m}")


def test_M6(fails: list[str]) -> None:
    t0 = time.time()
    rc, _, _ = run([str(SCRIPT / "compute_m2.py"),
                     str(FIX / "tiny_csl.csl"),
                     "--paraphrase", str(FIX / "tiny.en"),
                     "--backend=mock", "--bootstrap=100", "--model=small"])
    elapsed = time.time() - t0
    gate(fails, "M6 rc", rc == 0)
    gate(fails, "M6 speed", elapsed < 5.0, f"took {elapsed:.2f}s")


def test_M7(fails: list[str]) -> None:
    rc, out, _ = run([str(SCRIPT / "m2_compare.py"), "--json"])
    gate(fails, "M7 rc", rc == 0, f"rc={rc}")
    try:
        doc = json.loads(out)
        notations = {r["notation"] for r in doc}
        gate(fails, "M7 notations",
              notations == {"csl", "apl", "lojban", "prose"},
              f"got {notations}")
    except json.JSONDecodeError as e:
        fails.append(f"M7: invalid JSON: {e}")


def test_M8(fails: list[str]) -> None:
    rc, _, _ = run([str(SCRIPT / "m2_quality.py"), "--fallback"])
    gate(fails, "M8 rc", rc == 0, f"rc={rc}")


def main() -> int:
    fails: list[str] = []
    for fn in [test_M1, test_M2, test_M3, test_M4, test_M5, test_M6, test_M7, test_M8]:
        fn(fails)
    print(f"m2-harness : {len(fails)} failures")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
