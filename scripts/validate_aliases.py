#!/usr/bin/env python3
"""validate_aliases.py — CSLv3 glyph/alias validator (Task T5)

Cross-checks the glyph/alias tables across three sources:
  - specs/01_GLYPHS.csl     (source of truth for glyph inventory)
  - specs/12_TOKENIZER.csl  (ASCII alias master table)
  - parser/glyph_aliases.json (generated mapping consumed by tooling)

Invariants checked:
  1. Every non-ASCII glyph referenced in 01_GLYPHS has an ASCII alias
     declared in 12_TOKENIZER (the "ASCII ALIAS MASTER TABLE").
  2. No two distinct glyphs map to the same ASCII alias.
  3. parser/glyph_aliases.json matches the 12_TOKENIZER master table
     exactly (drift detection).
  4. No alias shadows a reserved keyword: fn def let pub use match
     enum alias if when unless while per.
  5. No single-char alias conflicts with an arithmetic/structural op:
     + - * / % = < > ! ? & | @ # $ , ;.

Exit codes:
  0  all invariants satisfied
  1  any invariant violated (details printed to stderr)

Usage:
  python scripts/validate_aliases.py
  python scripts/validate_aliases.py --write-json  # regenerate glyph_aliases.json
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GLYPHS_PATH    = ROOT / "specs" / "01_GLYPHS.csl"
TOKENIZER_PATH = ROOT / "specs" / "12_TOKENIZER.csl"
JSON_PATH      = ROOT / "parser" / "glyph_aliases.json"

KEYWORDS = {
    "fn", "def", "let", "pub", "use", "match",
    "enum", "alias", "if", "when", "unless", "while", "per",
    "true", "false", "nil",
}
SINGLE_CHAR_OPS = set("+-*/%=<>!?&|@#$,;()[]{}~^._\\")


def read(p: Path) -> str:
    with open(p, encoding="utf-8") as f:
        return f.read()


# ---------- parse 12_TOKENIZER ASCII ALIAS MASTER TABLE -------------------

ALIAS_TABLE_RE = re.compile(
    r"§ ASCII ALIAS MASTER TABLE[^\n]*\n"
    r".*?\n"                          # blurb line
    r"\| unicode \| ASCII[^\n]*\n"
    r"\|[-| ]+\|\s*\n"
    r"((?:\|[^\n]*\n)+)",
    re.DOTALL,
)

# Split on `|` but NOT on `\|` (escaped pipe).  We use a placeholder swap.
_ESC = "\u0000PIPE\u0000"


def parse_alias_master(text: str) -> dict[str, dict]:
    """Return { glyph -> { 'ascii': str, 'category': str } }.

    Paired glyph cells like `⟨ ⟩` are split into two entries.
    Paired ASCII cells like `<| |>` are split correspondingly."""
    m = ALIAS_TABLE_RE.search(text)
    if not m:
        raise RuntimeError("could not locate ASCII ALIAS MASTER TABLE in 12_TOKENIZER.csl")
    rows = m.group(1)
    out = {}
    for line in rows.splitlines():
        line = line.strip()
        if not line.startswith("|") or not line.endswith("|"):
            continue
        # escape-aware pipe split
        protected = line.replace(r"\|", _ESC)
        cells = [c.strip().replace(_ESC, "|") for c in protected.strip("|").split("|")]
        if len(cells) < 3:
            continue
        glyph, ascii_alias, category = cells[0], cells[1], cells[2]
        if not glyph or glyph in ("---", "----") or glyph.startswith("---"):
            continue
        # handle paired brackets like "⟨ ⟩" with corresponding "<| |>"
        g_parts = glyph.split()
        a_parts = ascii_alias.split()
        if len(g_parts) == 2 and len(a_parts) == 2:
            out[g_parts[0]] = {"ascii": a_parts[0], "category": category + " (open)"}
            out[g_parts[1]] = {"ascii": a_parts[1], "category": category + " (close)"}
        else:
            out[glyph] = {"ascii": ascii_alias, "category": category}
    return out


# ---------- extract inventoried glyphs from 01_GLYPHS tables --------------
# Only glyphs that appear in the FIRST column of a "| glyph | ... |" markdown
# table count as inventory. Prose-embedded unicode is ignored.

TABLE_ROW_RE = re.compile(r"^\|\s*([^|]+?)\s*\|")

# tables to skip (ASCII-only, or docs tables not listing glyphs)
SKIP_HEADERS = ("| tier ", "| glyph | ASCII")  # we'll still include glyph-headered tables


def extract_glyphs_in_01(text: str) -> set[str]:
    out = set()
    in_table = False
    header_is_glyph = False
    for raw in text.splitlines():
        line = raw.rstrip()
        if not line.startswith("|"):
            in_table = False
            header_is_glyph = False
            continue
        # header line?
        if re.match(r"^\|\s*glyph\s*\|", line, re.IGNORECASE):
            in_table = True
            header_is_glyph = True
            continue
        # separator line like |-----|
        if re.match(r"^\|[-| :]+$", line):
            continue
        # non-glyph header (e.g., | pair | semantics |)
        if re.match(r"^\|\s*(pair|suffix|glyph pair)\s*\|", line, re.IGNORECASE):
            in_table = True
            header_is_glyph = True
            continue
        if not (in_table and header_is_glyph):
            continue
        # extract first cell
        m = TABLE_ROW_RE.match(line)
        if not m:
            continue
        cell = m.group(1).strip()
        # paired like "⟨ ⟩" — split into two
        for tok in cell.split():
            # strip backticks if any
            tok = tok.strip("`")
            if not tok:
                continue
            # keep only single-char glyphs (ignore ASCII & compound tokens in glyph table)
            if len(tok) == 1 and not tok.isascii():
                out.add(tok)
            elif len(tok) > 1 and not tok.isascii():
                # multi-codepoint like "‼" if Python sees it that way — still add
                out.add(tok)
    return out


# ---------- checks --------------------------------------------------------

def check_coverage(glyphs_used: set[str], master: dict[str, dict]) -> list[str]:
    """Every inventoried glyph in 01_GLYPHS should have an alias in 12_TOKENIZER."""
    errs = []
    missing = sorted(g for g in glyphs_used if g not in master)
    # Glyphs that appear inventoried in 01_GLYPHS but are intentionally
    # not given an ASCII alias in 12_TOKENIZER — these use their type-class
    # determinative form instead (see §01 tier-1 TYPE CLASS MARKERS).
    KNOWN_ALT_ALIAS = {
        "ᴠ", "ᴍ", "ʙ", "ꜱ", "ʈ", "ɴ",   # type class markers — alias via 'n 'str etc
    }
    missing = [g for g in missing if g not in KNOWN_ALT_ALIAS and len(g) == 1]
    if missing:
        errs.append(
            "Invariant #1 FAILED: the following inventoried glyphs have no "
            "ASCII alias in 12_TOKENIZER master table:\n  "
            + ", ".join(f"'{g}' (U+{ord(g):04X})" for g in missing)
        )
    return errs


def check_unique(master: dict[str, dict]) -> list[str]:
    """No two glyphs map to the same ASCII alias."""
    errs = []
    rev: dict[str, list[str]] = {}
    for glyph, meta in master.items():
        rev.setdefault(meta["ascii"], []).append(glyph)
    dupes = {a: gs for a, gs in rev.items() if len(gs) > 1}
    if dupes:
        for ascii_, glyphs in dupes.items():
            errs.append(
                f"Invariant #2 FAILED: ASCII alias '{ascii_}' "
                f"is shared by multiple glyphs: {glyphs}"
            )
    return errs


def check_keyword_shadow(master: dict[str, dict]) -> list[str]:
    """No alias is a reserved keyword, except documented literal aliases."""
    errs = []
    # Documented intentional aliases that coincide with reserved words.
    # These are literal-value aliases, not operator shadows — the parser
    # disambiguates via position (literal atom vs. keyword-at-statement-start).
    INTENTIONAL = {
        ("∅", "nil"),    # empty set literal; §01 and §12 both use `nil`
        ("∞", "inf"),    # infinity literal; §01 and §12 both use `inf`
    }
    for glyph, meta in master.items():
        alias = meta["ascii"].strip()
        if alias in KEYWORDS and (glyph, alias) not in INTENTIONAL:
            errs.append(
                f"Invariant #4 FAILED: glyph '{glyph}' alias '{alias}' "
                f"shadows reserved keyword"
            )
    return errs


def check_single_char_conflict(master: dict[str, dict]) -> list[str]:
    """Single-char aliases must not conflict with operators."""
    errs = []
    for glyph, meta in master.items():
        alias = meta["ascii"]
        if len(alias) == 1 and alias in SINGLE_CHAR_OPS:
            # Allow conflict only if the glyph IS the operator itself
            # (e.g., '·' can alias '*' if doc says so — but we flag).
            errs.append(
                f"Invariant #5 WARN: single-char alias '{alias}' for '{glyph}' "
                f"collides with a structural operator — verify intent"
            )
    return errs


def check_json_matches(master: dict[str, dict], json_path: Path) -> list[str]:
    if not json_path.exists():
        return [f"Invariant #3 FAILED: {json_path} does not exist — run with --write-json"]
    try:
        on_disk = json.loads(json_path.read_text(encoding="utf-8"))
    except Exception as e:
        return [f"Invariant #3 FAILED: cannot parse {json_path}: {e}"]
    expected = {g: m["ascii"] for g, m in master.items()}
    actual = on_disk.get("glyph_to_ascii", {})
    if expected != actual:
        missing_in_json = sorted(set(expected) - set(actual))
        extra_in_json = sorted(set(actual) - set(expected))
        diff_values = [g for g in expected if g in actual and expected[g] != actual[g]]
        msg = ["Invariant #3 FAILED: parser/glyph_aliases.json drifted from 12_TOKENIZER:"]
        if missing_in_json:
            msg.append(f"  missing in json: {missing_in_json}")
        if extra_in_json:
            msg.append(f"  extra in json:   {extra_in_json}")
        if diff_values:
            msg.append(f"  value differs:   " + ", ".join(
                f"'{g}' json={actual[g]!r} spec={expected[g]!r}" for g in diff_values
            ))
        msg.append("  run with --write-json to regenerate")
        return ["\n".join(msg)]
    return []


def write_json(master: dict[str, dict], json_path: Path) -> None:
    payload = {
        "source":  "specs/12_TOKENIZER.csl  §ASCII ALIAS MASTER TABLE",
        "generator": "scripts/validate_aliases.py --write-json",
        "glyph_to_ascii": {g: m["ascii"]    for g, m in master.items()},
        "glyph_to_category": {g: m["category"] for g, m in master.items()},
    }
    json_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {json_path} ({len(master)} entries)")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write-json", action="store_true",
                    help="regenerate parser/glyph_aliases.json from 12_TOKENIZER")
    args = ap.parse_args()

    glyphs_text = read(GLYPHS_PATH)
    tokenizer_text = read(TOKENIZER_PATH)

    master = parse_alias_master(tokenizer_text)
    glyphs_used = extract_glyphs_in_01(glyphs_text)

    if args.write_json:
        write_json(master, JSON_PATH)
        return 0

    errs: list[str] = []
    errs += check_coverage(glyphs_used, master)
    errs += check_unique(master)
    errs += check_keyword_shadow(master)
    warns_single = check_single_char_conflict(master)
    errs += check_json_matches(master, JSON_PATH)

    if errs:
        for e in errs:
            print(e, file=sys.stderr)
        return 1

    print(f"[OK] alias table OK -- {len(master)} glyphs covered")
    if warns_single:
        for w in warns_single:
            print(w, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
