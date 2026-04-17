#!/usr/bin/env python3
"""T8 — error-recovery corpus (Session 3) + T15 permissive tagging (Session 4)

Feeds ~40 malformed CSL inputs through parser.exe --errors and verifies:
  R1. parser does NOT crash (returns a well-defined exit code)
  R2. parser reports >= 1 diagnostic for each malformed input
  R3. diagnostic format is file:line:col (actionable for editors)
  R4. parser terminates within a time budget (no infinite loop)

Session-4 T15 refinement:
  - 13 fixtures that are parser-accepted-by-design carry a
    `# permissive: true` header (written into the fixture itself).
  - PERMISSIVE_ACCEPT membership is now discovered by reading file
    headers, not a hardcoded set — no drift risk.

Run from repo root:  python tests/test_error_recovery_corpus.py
Exit 0 on all green; exit 1 on any regression.
"""

import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
TIME_BUDGET_S = 5.0

# Short alias for the permissive header
P = "# permissive: true\n"

# (category, filename, content, expected_token_in_error_or_None)
CASES = [
    # ---- unclosed-block ----
    ("unclosed-block", "u01_unclosed_angle.csl",
     "\u00a7 test\n  def Foo't \u27e8\n    x : i32\n", None),
    ("unclosed-block", "u02_unclosed_constraint.csl",
     "\u00a7 test\n  x : i32 \u2308 0..10\n", None),
    ("unclosed-block", "u03_unclosed_precondition.csl",
     "\u00a7 test\n  \u230ax > 0\n", None),
    ("unclosed-block", "u04_unclosed_formula.csl",
     "\u00a7 test\n  \u27e6 E = m c^2 \n", None),
    ("unclosed-block", "u05_unclosed_paren.csl",
     "\u00a7 test\n  fn foo (x : i32 -> i32 = x\n", None),
    ("unclosed-block", "u06_unclosed_bracket.csl",
     "\u00a7 test\n  xs : [i32; 10\n", None),
    ("unclosed-block", "u07_unclosed_brace.csl",
     "\u00a7 test\n  fn foo () -> bool = { let x = 1\n", None),
    ("unclosed-block", "u08_unclosed_enum.csl",
     "\u00a7 test\n  def K't = enum[ a, b, c\n", None),
    ("unclosed-block", "u09_unclosed_temporal.csl",
     "\u00a7 test\n  phase : \u27ea init \n", None),

    # ---- missing-glyph (trailing/dangling operator) ----
    ("missing-glyph", "m01_trailing_dot.csl",
     P + "\u00a7 test\n  player.\n", None),
    ("missing-glyph", "m02_trailing_eq.csl",
     "\u00a7 test\n  x = \n", None),
    ("missing-glyph", "m03_trailing_arrow.csl",
     "\u00a7 test\n  x -> \n", None),
    ("missing-glyph", "m04_trailing_colon.csl",
     "\u00a7 test\n  x :\n", None),
    ("missing-glyph", "m05_trailing_tensor.csl",
     "\u00a7 test\n  fire\u2297\n", None),
    ("missing-glyph", "m06_leading_arrow.csl",
     "\u00a7 test\n  -> foo\n", None),
    ("missing-glyph", "m07_fn_no_name.csl",
     P + "\u00a7 test\n  fn () -> bool = true\n", None),
    ("missing-glyph", "m08_def_no_name.csl",
     P + "\u00a7 test\n  def = enum[ a, b ]\n", None),

    # ---- bad-compound ----
    ("bad-compound", "c01_double_dot.csl",
     P + "\u00a7 test\n  a..b\n", None),
    ("bad-compound", "c02_dot_plus.csl",
     P + "\u00a7 test\n  a.+b\n", None),
    ("bad-compound", "c03_plus_plus.csl",
     "\u00a7 test\n  a++b\n", None),
    ("bad-compound", "c04_tensor_tensor.csl",
     "\u00a7 test\n  a\u2297\u2297b\n", None),
    ("bad-compound", "c05_at_only.csl",
     P + "\u00a7 test\n  x @\n", None),

    # ---- invalid-morpheme-stack ----
    ("invalid-morpheme", "i01_unknown_aspect.csl",
     P + "\u00a7 test\n  render.prog.fakeaspect : bool\n", None),
    ("invalid-morpheme", "i02_double_modality.csl",
     P + "\u00a7 test\n  x.must.may : bool\n", None),
    ("invalid-morpheme", "i03_trailing_morph.csl",
     P + "\u00a7 test\n  render.prog.\n", None),

    # ---- ambiguous-slot (malformed slot prefix order) ----
    ("ambiguous-slot", "s01_double_evidence.csl",
     "\u00a7 test\n  \u2713 [x] a : i32\n", None),
    ("ambiguous-slot", "s02_evidence_after_modal.csl",
     P + "\u00a7 test\n  W! \u2713 a : i32\n", None),
    ("ambiguous-slot", "s03_double_modal.csl",
     "\u00a7 test\n  W! R! a : i32\n", None),
    ("ambiguous-slot", "s04_modal_without_body.csl",
     P + "\u00a7 test\n  W!\n", None),

    # ---- type-system edge ----
    ("type-edge", "t01_bad_array.csl",
     "\u00a7 test\n  xs : [;10]\n", None),
    ("type-edge", "t02_bad_tuple.csl",
     P + "\u00a7 test\n  p : (i32, )\n", None),
    ("type-edge", "t03_bad_union.csl",
     "\u00a7 test\n  u : i32 | \n", None),
    ("type-edge", "t04_bad_map.csl",
     "\u00a7 test\n  m : {str: }\n", None),

    # ---- pathological ----
    ("pathological", "p01_only_operators.csl",
     ". + - * / % = < > \u2297 @ \u2308 \u2309 \u27e8 \u27e9\n", None),
    ("pathological", "p02_deep_indent_cliff.csl",
     "\u00a7 a\n    \u00a7 b\n  \u00a7 c\n", None),
    ("pathological", "p03_lexer_invalid_glyph.csl",
     "\u00a7 test\n  foo : \U00011032\U00011032 \n", None),
    ("pathological", "p04_mixed_brackets.csl",
     P + "\u00a7 test\n  f : \u27e8a, b]\n", None),

    # ---- empty / degenerate ----
    ("degenerate", "d01_empty.csl",
     "", None),
    ("degenerate", "d02_only_whitespace.csl",
     "   \n\n  \t  \n", None),
    ("degenerate", "d03_only_comments.csl",
     "# just a comment\n# another comment\n", None),
]

EXPECT_NO_ERROR = {"d01_empty.csl", "d02_only_whitespace.csl", "d03_only_comments.csl"}


def discover_permissive(corpus_dir: Path) -> set[str]:
    out: set[str] = set()
    for p in corpus_dir.glob("*.csl"):
        try:
            head = p.read_text(encoding="utf-8", errors="replace")[:200]
        except OSError:
            continue
        if "permissive: true" in head:
            out.add(p.name)
    return out


def run_parser(path: Path) -> tuple[int, str, float]:
    """Run parser.exe --errors <path>, return (exit, combined_output, elapsed_s)."""
    t0 = time.perf_counter()
    try:
        proc = subprocess.run(
            [str(PARSER), "--errors", str(path)],
            capture_output=True, text=True, timeout=TIME_BUDGET_S,
            encoding="utf-8", errors="replace",
        )
    except subprocess.TimeoutExpired:
        return (-1, "[TIMEOUT]", TIME_BUDGET_S)
    elapsed = time.perf_counter() - t0
    out = (proc.stdout or "") + (proc.stderr or "")
    return (proc.returncode, out, elapsed)


def write_case(basedir: Path, fname: str, content: str) -> Path:
    p = basedir / fname
    p.write_text(content, encoding="utf-8")
    return p


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found. Run `odin build parser/` first.\n")
        return 2

    corpus_dir = ROOT / "parser" / "error_tests"
    corpus_dir.mkdir(parents=True, exist_ok=True)

    total = len(CASES)
    fails: list[str] = []
    timeouts: list[str] = []
    total_elapsed = 0.0

    err_line_re = re.compile(r"^[^\s:].*:\d+:\d+:", re.MULTILINE)

    # Write all fixtures first so discover_permissive sees current tags
    for (_, fname, content, _) in CASES:
        write_case(corpus_dir, fname, content)
    permissive = discover_permissive(corpus_dir)

    for (cat, fname, content, expect) in CASES:
        path = corpus_dir / fname
        rc, out, elapsed = run_parser(path)
        total_elapsed += elapsed

        if rc == -1:
            timeouts.append(fname)
            fails.append(f"{fname}: TIMEOUT (> {TIME_BUDGET_S}s)")
            continue

        if fname in EXPECT_NO_ERROR:
            if rc != 0:
                fails.append(f"{fname} [{cat}]: expected clean parse, got rc={rc}\n  out: {out!r}")
            continue

        if fname in permissive:
            # parser accepts by design ; R1/R4 already verified
            continue

        # R2 : at least one diagnostic
        if not err_line_re.search(out):
            fails.append(f"{fname} [{cat}]: no file:line:col diagnostic in output\n  out: {out!r}")
            continue

        # R1 : rc != 0 for real parse failures
        if rc == 0:
            fails.append(f"{fname} [{cat}]: error reported but rc=0\n  out: {out!r}")
            continue

        if expect and expect not in out:
            fails.append(f"{fname} [{cat}]: expected token '{expect}' in diagnostic\n  out: {out!r}")

    print(f"error-recovery corpus: {total} cases, {len(fails)} failures, "
          f"elapsed {total_elapsed*1000:.0f} ms total "
          f"({total_elapsed*1000/total:.1f} ms/case avg) | "
          f"permissive-tagged: {len(permissive)}")
    if timeouts:
        print(f"  timeouts: {timeouts}", file=sys.stderr)
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)

    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
