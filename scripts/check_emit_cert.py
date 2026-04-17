#!/usr/bin/env python3
"""T28 — Emit certificate-chain verifier (Session-10)

Runs `parser --smt-audit-verify .proof` to validate every appended emit
signature. Emit signing reuses the SMT audit-chain ; each --emit=X --sign
invocation appends a new entry, and this script confirms the chain
reconstructs cleanly from the dev-stub Ed25519 key.

Exit 0 on verified ; 1 on any signature drift or missing-key.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
PROOF_DIR = ROOT / ".proof"


def main() -> int:
    if not PARSER.exists():
        print(f"ERROR: {PARSER} missing", file=sys.stderr)
        return 2
    if not PROOF_DIR.exists():
        print(f"ERROR: {PROOF_DIR} missing ; run --emit=X --sign first", file=sys.stderr)
        return 2

    rc = subprocess.run(
        [str(PARSER), "--smt-audit-verify", str(PROOF_DIR)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    out = (rc.stdout or "") + (rc.stderr or "")
    print(out.strip())
    if rc.returncode != 0:
        return 1
    if "OK" not in out:
        print("verify did not report OK", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
