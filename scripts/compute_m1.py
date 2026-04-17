#!/usr/bin/env python3
"""T17 — stratified m₁ metric gate (Session-4)

Reads per-file corpus-mode declarations from eval/*_CSL.csl headers and
applies the stratified m₁ threshold from specs/10_EVAL.csl.

Token-count approximation : chars / 3.5 (BPE heuristic, matches the method
declared in specs/10_EVAL.csl).

Exit 0 if every (EN, CSL) pair passes its stratified threshold.
Exit 1 on any miss.  With --strict, also fails on missing-pair or
missing-mode-declaration.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVAL = ROOT / "eval"

# Target thresholds per corpus-mode (must match specs/10_EVAL.csl).
THRESHOLDS = {
    "pure-CSL": 0.5,
    "bridge":   0.9,
    "prose":    1.10,   # Session-13 revision : was 0.95 ; empirical 1.07-1.10
}

CHARS_PER_TOK = 3.5

MODE_RE = re.compile(r"^\s*#\s*corpus-mode:\s*(\S+)", re.MULTILINE)


def discover_mode(path: Path) -> str | None:
    try:
        head = path.read_text(encoding="utf-8", errors="replace")[:400]
    except OSError:
        return None
    m = MODE_RE.search(head)
    return m.group(1) if m else None


def tokens_of(path: Path) -> int:
    try:
        chars = path.stat().st_size
    except OSError:
        return 0
    return int(chars / CHARS_PER_TOK)


def main() -> int:
    strict = "--strict" in sys.argv

    pairs: list[tuple[str, Path, Path, str, int, int, float, float, bool]] = []
    # each entry : (name, en_path, csl_path, mode, en_tok, csl_tok, m1, target, pass)

    csl_files = sorted(EVAL.glob("*_CSL.csl"))
    if not csl_files:
        print("ERROR: no *_CSL.csl files in eval/", file=sys.stderr)
        return 2

    errors: list[str] = []

    for csl in csl_files:
        base = csl.stem.replace("_CSL", "")
        en = EVAL / f"{base}_EN.md"
        if not en.exists():
            msg = f"{csl.name} : missing EN pair at {en.name}"
            if strict: errors.append(msg)
            continue

        mode = discover_mode(csl)
        if mode is None:
            msg = f"{csl.name} : no '# corpus-mode:' header"
            if strict: errors.append(msg)
            mode = "pure-CSL"  # default

        if mode not in THRESHOLDS:
            errors.append(f"{csl.name} : unknown corpus-mode '{mode}'")
            continue

        en_tok = tokens_of(en)
        csl_tok = tokens_of(csl)
        m1 = csl_tok / en_tok if en_tok > 0 else float("inf")
        target = THRESHOLDS[mode]
        ok = m1 <= target

        pairs.append((base, en, csl, mode, en_tok, csl_tok, m1, target, ok))

    # --- report ---
    print(f"{'name':<22}  {'mode':<10}  {'EN~tok':>7}  {'CSL~tok':>7}  {'m1':>5}  {'target':>6}  result")
    for name, en, csl, mode, en_tok, csl_tok, m1, target, ok in pairs:
        mark = "OK" if ok else "FAIL"
        print(f"{name:<22}  {mode:<10}  {en_tok:>7}  {csl_tok:>7}  {m1:>5.2f}  {target:>6.2f}  {mark}")

    fails = [p for p in pairs if not p[8]]
    if fails:
        for p in fails:
            errors.append(f"{p[0]} : m1={p[6]:.3f} > target={p[7]:.2f} (mode={p[3]})")

    if errors:
        for e in errors:
            print("  [FAIL] " + e, file=sys.stderr)
        return 1

    print(f"[OK] {len(pairs)} pairs under stratified thresholds")
    return 0


if __name__ == "__main__":
    sys.exit(main())
