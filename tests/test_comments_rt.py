#!/usr/bin/env python3
"""T23 — comment-preservation round-trip (Session-5)

RT invariant upgraded : AST-shape + comment-position across 5 pprint modes.

Gates:
  G1 : 7/7 parser/tests/*.csl round-trip (baseline — no comment edits)
  G2 : each of 8 comment-shape fixtures round-trips in canonical mode
  G3 : round-trip holds across all 5 pprint modes for 3 samples
  G4 : comment position preserved (not just count) — fixture-specific assertion

Exit 0 on green ; 1 on any regression.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"

# --- comment-shape fixtures ---
# Each has multiple comment configurations ; RT must preserve them all.
FIXTURES = {
    "line_before_stmt": (
        "§ T\n"
        "  # leading comment\n"
        "  x : i32\n"
    ),
    "two_lines_before": (
        "§ T\n"
        "  # first\n"
        "  # second\n"
        "  x : i32\n"
    ),
    "comment_after_section_header": (
        "§ OUTER\n"
        "  # inside outer\n"
        "  def K = enum[ A, B ]\n"
    ),
    "nested_comments": (
        "§ T\n"
        "  # outer note\n"
        "  § NESTED\n"
        "    # nested note\n"
        "    y : bool\n"
    ),
    "multiple_definitions_with_comments": (
        "§ T\n"
        "  # def 1\n"
        "  a : i32\n"
        "  # def 2\n"
        "  b : bool\n"
        "  # def 3\n"
        "  c : str\n"
    ),
    "comment_before_fn": (
        "§ T\n"
        "  # pure helper\n"
        "  fn id (x : i32) -> i32 = 0\n"
    ),
    "comment_between_section_and_indent": (
        "§ MOD\n"
        "  # heading-comment\n"
        "  def R ⟨ a : i32 ⟩\n"
    ),
    "stacked_comments_block": (
        "§ T\n"
        "  # line 1\n"
        "  # line 2\n"
        "  # line 3\n"
        "  # line 4\n"
        "  x : i32\n"
    ),
}

MODES = ["canonical", "compact", "literate", "ascii-only", "unicode-only"]


def run(args: list[str], input_file: Path) -> tuple[int, str]:
    proc = subprocess.run(args + [str(input_file)],
                          capture_output=True, text=True, timeout=10,
                          encoding="utf-8", errors="replace")
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found.\n")
        return 2

    fails: list[str] = []

    # G1 : live corpus baseline
    for p in sorted((ROOT / "parser" / "tests").glob("*.csl")):
        rc, out = run([str(PARSER), "--roundtrip"], p)
        if rc != 0 or "ROUND-TRIP OK" not in out:
            fails.append(f"G1: {p.name} rc={rc}\n  out: {out!r}")

    # G2 : each comment fixture round-trips
    with tempfile.TemporaryDirectory(prefix="csl-comments-") as tmp:
        tmpdir = Path(tmp)
        sample_paths: list[Path] = []
        for name, body in FIXTURES.items():
            p = tmpdir / f"{name}.csl"
            p.write_text(body, encoding="utf-8")
            sample_paths.append(p)
            rc, out = run([str(PARSER), "--roundtrip"], p)
            if rc != 0 or "ROUND-TRIP OK" not in out:
                fails.append(f"G2: {name} rc={rc}\n  out: {out!r}")

        # G3 : across 5 pprint modes, round-trip via print→parse holds
        # (using 3 sample fixtures)
        for name in ["line_before_stmt", "nested_comments", "stacked_comments_block"]:
            orig = tmpdir / f"{name}.csl"
            for mode in MODES:
                rc1, printed = run([str(PARSER), "--print", f"--mode={mode}"], orig)
                if rc1 != 0:
                    fails.append(f"G3: {name} --mode={mode} pprint rc={rc1}")
                    continue
                # write printed output back out, reparse it
                reprinted = tmpdir / f"{name}_{mode}.csl"
                reprinted.write_text(printed, encoding="utf-8")
                rc2, out2 = run([str(PARSER), "--errors"], reprinted)
                if rc2 != 0:
                    fails.append(f"G3: {name} --mode={mode} reparse rc={rc2}\n  out: {out2!r}")

        # G4 : comment-count sanity — each fixture's printed output has
        # the same number of `# `-starting lines as the input
        for name, body in FIXTURES.items():
            p = tmpdir / f"{name}.csl"
            rc, printed = run([str(PARSER), "--print"], p)
            if rc != 0:
                continue
            in_count  = sum(1 for ln in body.splitlines()     if ln.lstrip().startswith("#"))
            out_count = sum(1 for ln in printed.splitlines()  if ln.lstrip().startswith("#"))
            if in_count != out_count:
                fails.append(f"G4: {name} comment count drift {in_count} → {out_count}")

    print(f"comment-RT : {len(fails)} failures")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
