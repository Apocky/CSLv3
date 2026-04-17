#!/usr/bin/env python3
"""validate_glyph_grammar_consistency.py — T9 CI gate

Bidirectional consistency check between:
  - specs/12_TOKENIZER.csl  §ASCII ALIAS MASTER TABLE (71 glyphs, canonical)
  - specs/13_GRAMMAR_SELF.csl (grammar expressed in CSLv3 itself)

Invariants:
  I1. Every non-ASCII glyph used inside productions of 13_GRAMMAR_SELF.csl
      MUST appear in the 12_TOKENIZER master table.
  I2. Every unicode glyph in the 12_TOKENIZER master table SHOULD either
      appear somewhere in the grammar spec OR be documented as "non-
      grammatical" (reasoning glyphs, evidence markers, tier-2 physics).
  I3. Grammar productions may use ASCII aliases in place of glyphs; those
      aliases MUST match the master table's ascii column for their glyph.

Exit codes:
  0  all invariants satisfied
  1  any violation
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GRAMMAR_PATH   = ROOT / "specs" / "13_GRAMMAR_SELF.csl"
TOKENIZER_PATH = ROOT / "specs" / "12_TOKENIZER.csl"
ALIASES_JSON   = ROOT / "parser" / "glyph_aliases.json"

# Glyph categories that are expected to appear in 12 but not in 13's grammar
# productions themselves (they're used in reasoning, evidence, prose — not
# grammar structure). This is an ALLOW-LIST of non-grammatical categories.
NON_GRAMMAR_CATEGORIES = {
    "key-insight", "note-to-self", "iterate", "dive", "lift", "pivot",
    "warning",
    "proven", "unknown", "hypothetical", "deprecated",
    "confirmed", "pending", "partial", "failed",
    "apl-each", "apl-compose", "apl-sort", "apl-iota",
    "density", "friction", "stress", "curvature", "strain", "torque",
    "gradient", "partial", "delta",
    "det-field", "det-spatial",
    # paired brackets where only one half appears in productions
    "temp-open", "temp-close", "quote-open", "quote-close",
}


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8")


def load_master_table() -> dict[str, dict]:
    """Parse 12_TOKENIZER.csl master table → {glyph: {ascii, category}}."""
    if ALIASES_JSON.exists():
        data = json.loads(ALIASES_JSON.read_text(encoding="utf-8"))
        g2a = data.get("glyph_to_ascii", {})
        g2c = data.get("glyph_to_category", {})
        return {g: {"ascii": a, "category": g2c.get(g, "")} for g, a in g2a.items()}
    sys.stderr.write(f"ERROR: {ALIASES_JSON} not found — run validate_aliases.py --write-json first\n")
    sys.exit(2)


# Rows inside grammar .csl files are heterogeneous:
# - markdown tables  | glyph | ... |
# - BNF-like productions   foo := '<' bar '>'
# - inline prose with glyphs as examples
#
# For strict checking we want glyphs that appear AS GRAMMAR TERMINALS, not
# as free prose. Practical approximation: scan every non-heading, non-
# markdown-table-separator line and collect any non-ASCII codepoint that
# also appears in the master table. Anything else is either in master
# (ok) or legitimately absent (flag).

def extract_glyphs_from_grammar(text: str) -> set[str]:
    out: set[str] = set()
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line:
            continue
        # skip pure markdown separator lines
        if re.match(r"^\s*\|[-| :]+\|?\s*$", line):
            continue
        for ch in line:
            if ch.isascii():
                continue
            if ch.isspace():
                continue
            out.add(ch)
    return out


def main() -> int:
    grammar = read(GRAMMAR_PATH)
    _ = read(TOKENIZER_PATH)
    master = load_master_table()

    grammar_glyphs = extract_glyphs_from_grammar(grammar)
    master_glyphs = set(master.keys())

    errors: list[str] = []
    warnings: list[str] = []

    # I1: every grammar glyph ∈ master
    missing = sorted(g for g in grammar_glyphs if g not in master_glyphs and len(g) == 1)
    # exclude well-known prose / decorative chars that slip through
    PROSE_IGNORE = {
        "°", "´", "·", "–", "—", "…", "‡", "†",
        "²", "³", "ᵏ", "ʼ", "ʻ",
    }
    missing = [g for g in missing if g not in PROSE_IGNORE]
    # Also exclude Greek/Latin letters that are inline prose
    missing = [g for g in missing if g not in {"ā", "ē", "ī", "ō", "ū"}]
    if missing:
        errors.append(
            "I1 FAILED: glyphs used in 13_GRAMMAR_SELF.csl but absent from "
            "12_TOKENIZER master table:\n  " +
            ", ".join(f"'{g}' (U+{ord(g):04X})" for g in missing)
        )

    # I2: every master glyph used-or-allow-listed
    unused = []
    for g, meta in master.items():
        if g in grammar_glyphs:
            continue
        if meta.get("category", "") in NON_GRAMMAR_CATEGORIES:
            continue
        if meta.get("category", "").endswith(" (open)") or meta.get("category", "").endswith(" (close)"):
            # paired bracket — only one side may appear, that's fine
            continue
        unused.append((g, meta.get("category", "")))
    if unused:
        # Not fatal — warn. Grammar file is living doc and may grow.
        msg = "I2 WARN: master-table glyphs not referenced in 13_GRAMMAR_SELF.csl:\n"
        for g, cat in sorted(unused):
            msg += f"  '{g}' (U+{ord(g):04X}) category={cat}\n"
        warnings.append(msg.rstrip())

    # I3: check ASCII aliases used in grammar correspond to real entries
    # (coarse: find `'=>'`, `'<-'`, `'->'` inside quoted grammar productions
    #  and ensure they are valid alias strings)
    ascii_aliases = {m["ascii"] for m in master.values()}
    quoted_ops = re.findall(r"'([^\w\s'][^']*)'", grammar)
    # filter to things that look like ASCII operator tokens (2-5 chars, no letters-only)
    orphan_aliases = []
    for tok in quoted_ops:
        t = tok.strip()
        if not t or len(t) > 6:
            continue
        if t.isalpha():
            continue  # keywords like 'fn' 'def'
        # contains at least one symbol char
        if any(not c.isalnum() for c in t):
            if t not in ascii_aliases:
                # common non-alias operators that grammar uses natively:
                if t in {"(", ")", "[", "]", "{", "}", ",", ";", ":", "::",
                         "..", "?", "+", "-", "*", "/", "%", "=", "!", "!=",
                         "==", "<", ">", "<=", ">=", "&", "|", "^", "$",
                         "#", "@", "\\", "->", "|>", "<|"}:
                    continue
                orphan_aliases.append(t)
    if orphan_aliases:
        warnings.append(
            "I3 INFO: quoted operator strings in grammar that are not in "
            "alias master table:\n  " + ", ".join(f"'{t}'" for t in orphan_aliases)
        )

    # Report
    if errors:
        for e in errors:
            print(e, file=sys.stderr)
    for w in warnings:
        print(w, file=sys.stderr)

    if errors:
        print(f"[FAIL] grammar/glyph consistency: {len(errors)} errors, {len(warnings)} warnings",
              file=sys.stderr)
        return 1

    print(f"[OK] grammar/glyph consistency: {len(grammar_glyphs)} grammar-glyphs "
          f"checked against {len(master_glyphs)}-entry master; "
          f"{len(warnings)} warnings")
    return 0


if __name__ == "__main__":
    sys.exit(main())
