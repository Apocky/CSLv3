#!/usr/bin/env python3
"""T25.9 — m₂ audit-chain tests (Session-11).

Gates:
  A1 : --init creates .m2-chain/keys/{private,public}.key + genesis entry
  A2 : --append after --all-eval baseline writes 1-per-measurement entries
  A3 : --verify reports OK on freshly-written chain (all signatures valid)
  A4 : tampering with a chain entry makes --verify fail
  A5 : chain file is JSONL (one JSON object per line) and parseable
  A6 : Genesis entry has seq=0 + prev_hash="" + run_id=GENESIS

Exit 0 on green ; 1 on any regression.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts"
CHAIN  = ROOT / ".m2-chain"


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


def reset_chain() -> None:
    if CHAIN.exists():
        shutil.rmtree(CHAIN, ignore_errors=True)


def test_A1_A6(fails: list[str]) -> None:
    reset_chain()
    rc, _, _ = run([str(SCRIPT / "m2_audit.py"), "--init"])
    gate(fails, "A1 init rc", rc == 0, f"rc={rc}")
    gate(fails, "A1 priv-key", (CHAIN / "keys" / "private.key").exists())
    gate(fails, "A1 pub-key",  (CHAIN / "keys" / "public.key").exists())
    gate(fails, "A1 chain",    (CHAIN / "runs.jsonl").exists())

    # A6 : genesis shape
    if (CHAIN / "runs.jsonl").exists():
        first_line = (CHAIN / "runs.jsonl").read_text(encoding="utf-8").splitlines()[0]
        d = json.loads(first_line)
        gate(fails, "A6 seq=0",         d["seq"] == 0)
        gate(fails, "A6 prev_hash=''",  d["prev_hash"] == "")
        gate(fails, "A6 run=GENESIS",   d["run_id"] == "GENESIS")


def test_A2_A3_A5(fails: list[str]) -> None:
    reset_chain()
    # Rebuild baseline via mock backend (quick)
    rc, _, _ = run([str(SCRIPT / "compute_m2.py"),
                     "--all-eval", "--backend=mock", "--bootstrap=50"])
    gate(fails, "A2 baseline rc", rc == 0)

    rc, out, _ = run([str(SCRIPT / "m2_audit.py"),
                       "--append", str(ROOT / "eval" / "m2_baseline.json")])
    gate(fails, "A2 append rc", rc == 0, f"rc={rc}")
    gate(fails, "A2 append count", "appended 21 entries" in out,
          f"out-tail: {out[-200:]}")

    # A5 : JSONL parseable, one JSON per line
    lines = (CHAIN / "runs.jsonl").read_text(encoding="utf-8").splitlines()
    gate(fails, "A5 line count", len(lines) == 22,
          f"got {len(lines)} lines (want 22 = genesis + 21)")
    for i, line in enumerate(lines):
        try:
            json.loads(line)
        except json.JSONDecodeError as e:
            fails.append(f"A5 line {i}: {e}")
            break

    # A3 : verify
    rc, out, _ = run([str(SCRIPT / "m2_audit.py"), "--verify"])
    gate(fails, "A3 verify rc", rc == 0, f"rc={rc}")
    gate(fails, "A3 verify OK", "OK" in out, f"out: {out[-200:]}")


def test_A4(fails: list[str]) -> None:
    """Tamper with a chain entry → verify should fail."""
    chain_file = CHAIN / "runs.jsonl"
    if not chain_file.exists():
        fails.append("A4: chain missing (A2 setup failure upstream)")
        return
    original = chain_file.read_text(encoding="utf-8")

    # Corrupt a middle entry's m2_value
    lines = original.splitlines()
    if len(lines) < 3:
        fails.append("A4: chain too short to tamper (need > 2 entries)")
        return
    d = json.loads(lines[2])
    d["m2_value"] = 99.999
    lines[2] = json.dumps(d, ensure_ascii=False)
    chain_file.write_text("\n".join(lines) + "\n", encoding="utf-8")

    rc, out, _ = run([str(SCRIPT / "m2_audit.py"), "--verify"])
    gate(fails, "A4 tamper detected", rc != 0 and "OK" not in out,
          f"rc={rc} out={out[-200:]}")

    # Restore
    chain_file.write_text(original, encoding="utf-8")


def main() -> int:
    fails: list[str] = []
    # Require the cryptography module ; skip gracefully if not installed.
    try:
        import cryptography  # noqa: F401
    except ImportError:
        print("m2-audit : SKIP (cryptography not installed)")
        return 0

    test_A1_A6(fails)
    test_A2_A3_A5(fails)
    test_A4(fails)
    print(f"m2-audit : {len(fails)} failures")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
