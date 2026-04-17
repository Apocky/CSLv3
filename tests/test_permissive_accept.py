#!/usr/bin/env python3
"""T15 — PERMISSIVE_ACCEPT contract

Validates:
  G1. Every fixture tagged '# permissive: true' parses (no crash, no exit 2).
  G2. Count of tagged fixtures matches the current spec count (13).
  G3. Under --strict-parse, at least a documented subset of permissive
      fixtures produce exit 1. Fixtures whose permissive shape is
      parser-only (not semantically detectable without parser changes)
      are documented in GAPS below and excluded from the must-fail set.
  G4. No fixture loses its header tag (regression check).

Exit 0 on pass; 1 otherwise.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORPUS = ROOT / "parser" / "error_tests"
PARSER = ROOT / "parser.exe"

# Expected tagged count per Session-4 T15 spec.
EXPECTED_TAGGED_COUNT = 13

# Permissive shapes the semantic analyzer CAN detect today (fires
# Permissive_Accept W by default, E under --strict-parse).
# Session-5 T22 closes the former 5 gaps (c01 c02 s02 t02 p04).
SEMANTICALLY_DETECTED = {
    "m07_fn_no_name.csl",          # anonymous fn
    "m08_def_no_name.csl",         # anonymous type
    "m01_trailing_dot.csl",        # trailing dot → node.meta starts '.'
    "i03_trailing_morph.csl",      # trailing dot → node.meta starts '.'
    "c05_at_only.csl",             # trailing `@` → node.meta starts '@'
    "s04_modal_without_body.csl",  # bare modal directive
    # T22 additions :
    "c01_double_dot.csl",          # range-stmt marker
    "c02_dot_plus.csl",            # meta="." already via Session-4 T15
    "s02_evidence_after_modal.csl",# slot-order marker
    "t02_bad_tuple.csl",           # trailing-comma marker
    "p04_mixed_brackets.csl",      # parse-error path (always rc=1)
}

# Session-4 GAPS list is empty post-T22.
GAPS = set()

# Fixtures that fire a DIFFERENT semantic error severe enough to fail
# --strict-parse on its own (dup-morph=E always).
INDIRECT_FAIL_UNDER_STRICT_PARSE = {
    "i02_double_modality.csl",     # duplicate morpheme → E always
}

# Fixtures whose permissive shape only fails under --strict (not --strict-parse)
# because the detection is via morpheme-checks, not Permissive_Accept code.
# Per Q2/Q3 : --strict-parse elevates only Permissive_Accept ; --strict elevates
# Morph_Order and Morph_Unknown.
REQUIRES_STRICT_NOT_STRICT_PARSE = {
    "i01_unknown_aspect.csl",      # unknown-morpheme-after-stack (W default, E strict)
}


def run(args: list[str]) -> tuple[int, str]:
    proc = subprocess.run(args, capture_output=True, text=True, timeout=10,
                          encoding="utf-8", errors="replace")
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found.\n")
        return 2

    fails: list[str] = []

    # --- G4 / G2 : discover tagged fixtures and count them ---
    tagged: list[Path] = []
    for p in sorted(CORPUS.glob("*.csl")):
        head = p.read_text(encoding="utf-8", errors="replace")[:200]
        if "permissive: true" in head:
            tagged.append(p)

    if len(tagged) != EXPECTED_TAGGED_COUNT:
        fails.append(f"G2: expected {EXPECTED_TAGGED_COUNT} tagged fixtures, found {len(tagged)}")

    tagged_names = {p.name for p in tagged}

    # --- G1 : no crash on --errors ---
    for p in tagged:
        rc, _ = run([str(PARSER), "--errors", str(p)])
        if rc not in (0, 1):
            fails.append(f"G1: {p.name} exit={rc} (expected 0 or 1, not crash/usage-err)")

    # --- G3 : --strict-parse exits 1 on (SEMANTICALLY_DETECTED ∪ INDIRECT_FAIL) ---
    must_fail_strict_parse = SEMANTICALLY_DETECTED | INDIRECT_FAIL_UNDER_STRICT_PARSE
    must_fail_strict = must_fail_strict_parse | REQUIRES_STRICT_NOT_STRICT_PARSE
    # Sanity-check partition
    partition_problems = []
    for name in tagged_names:
        in_sd = name in SEMANTICALLY_DETECTED
        in_gaps = name in GAPS
        in_ind = name in INDIRECT_FAIL_UNDER_STRICT_PARSE
        in_rs = name in REQUIRES_STRICT_NOT_STRICT_PARSE
        if not (in_sd or in_gaps or in_ind or in_rs):
            partition_problems.append(f"G3-setup: {name} not categorised")
    if partition_problems:
        fails.extend(partition_problems)

    # G3 : verify --strict-parse on SEMANTICALLY_DETECTED ∪ INDIRECT
    for p in tagged:
        if p.name not in must_fail_strict_parse:
            continue
        rc, out = run([str(PARSER), "--semantic", "--strict-parse", str(p)])
        if rc != 1:
            fails.append(f"G3: {p.name} --strict-parse rc={rc} want=1\n  out(head): {out[:200]!r}")

    # G3b : verify --strict on full must-fail set (including REQUIRES_STRICT)
    for p in tagged:
        if p.name not in must_fail_strict:
            continue
        rc, out = run([str(PARSER), "--semantic", "--strict", str(p)])
        if rc != 1:
            fails.append(f"G3b: {p.name} --strict rc={rc} want=1\n  out(head): {out[:200]!r}")

    # --- Info : print status ---
    print(f"T15 permissive-accept contract : {len(tagged)}/{EXPECTED_TAGGED_COUNT} tagged")
    print(f"  semantically detected : {len(SEMANTICALLY_DETECTED)}")
    print(f"  indirect-fail-under-strict-parse : {len(INDIRECT_FAIL_UNDER_STRICT_PARSE)}")
    print(f"  documented gaps : {len(GAPS)}")
    if fails:
        for f in fails:
            print("  [FAIL] " + f, file=sys.stderr)
        return 1
    print("  all gates green")
    return 0


if __name__ == "__main__":
    sys.exit(main())
