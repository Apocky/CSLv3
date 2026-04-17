#!/usr/bin/env python3
"""T18 — tier-2 physics-glyph usage audit (Session-4)

Target glyphs (from specs/01_GLYPHS.csl TIER-2 PHYSICS/MATERIAL):
    ρ μ σ κ ε τ

Scans specs/*.csl + eval/*.csl + parser/tests/*.csl + examples/*.csl +
parser/error_tests/*.csl for occurrences. Classifies each glyph:

  - USED (≥ 1 site outside disclaimers) : keep + document sites
  - PROSE-ONLY (only in disclaimers / comments, never in data) : evaluate
  - UNUSED (no occurrences anywhere)   : recommend demote-to-tier3 or delete

Writes audit to diag/TIER2_USAGE_AUDIT.md with per-glyph sites and
a recommendation block. Does NOT delete anything — Apocky-authorization
required per T18 spec non-goal.

Exit 0 always (informational audit).
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "diag" / "TIER2_USAGE_AUDIT.md"

TIER2 = {
    "ρ": ("rho",   "density"),
    "μ": ("mu",    "friction"),
    "σ": ("sigma", "stress"),
    "κ": ("kappa", "curvature"),
    "ε": ("eps",   "strain"),
    "τ": ("tau",   "torque"),
}

# Files known to be glyph-inventories (mention glyphs in prose / tables
# without semantic use). Findings in these are "inventory mentions" rather
# than "active use".
INVENTORY_FILES = {
    "specs/01_GLYPHS.csl",
    "specs/12_TOKENIZER.csl",
    "parser/glyph_aliases.json",
}

# Directories to scan
SCAN_DIRS = ["specs", "eval", "parser/tests", "examples", "parser/error_tests"]


def rel(p: Path) -> str:
    try:
        return str(p.relative_to(ROOT)).replace("\\", "/")
    except ValueError:
        return str(p)


def scan() -> dict[str, list[tuple[str, int, str]]]:
    """Return { glyph: [(file, lineno, snippet), ...] }."""
    found: dict[str, list[tuple[str, int, str]]] = {g: [] for g in TIER2}
    for d in SCAN_DIRS:
        base = ROOT / d
        if not base.is_dir():
            continue
        for p in base.rglob("*"):
            if not p.is_file():
                continue
            if p.suffix not in {".csl", ".md", ".json"}:
                continue
            try:
                text = p.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for i, line in enumerate(text.splitlines(), start=1):
                for g in TIER2:
                    if g in line:
                        found[g].append((rel(p), i, line.strip()))
    return found


def classify(sites: list[tuple[str, int, str]]) -> str:
    """Return 'UNUSED' | 'INVENTORY-ONLY' | 'USED'."""
    if not sites:
        return "UNUSED"
    for file, _, _ in sites:
        if file not in INVENTORY_FILES:
            return "USED"
    return "INVENTORY-ONLY"


def main() -> int:
    OUT.parent.mkdir(parents=True, exist_ok=True)

    found = scan()

    lines = ["# TIER-2 PHYSICS-GLYPH USAGE AUDIT (Session-4 T18)",
             "",
             "Target glyphs: ρ μ σ κ ε τ (from specs/01_GLYPHS.csl TIER-2).",
             "",
             "Inventory files (mentions here don't count as 'active use'):",
             ""]
    for f in sorted(INVENTORY_FILES):
        lines.append(f"  - `{f}`")
    lines.append("")

    # Summary table
    lines.append("## Summary")
    lines.append("")
    lines.append("| glyph | ASCII | domain    | sites | classification    | recommendation              |")
    lines.append("|-------|-------|-----------|------:|-------------------|-----------------------------|")
    recommend: dict[str, str] = {}
    for g, (ascii_alias, domain) in TIER2.items():
        sites = found[g]
        cls = classify(sites)
        if cls == "UNUSED":
            rec = "demote to tier-3 or delete (Apocky approval)"
        elif cls == "INVENTORY-ONLY":
            rec = "keep in inventory; no downstream use yet"
        else:
            rec = "keep (active)"
        recommend[g] = cls
        lines.append(f"| `{g}`   | `{ascii_alias:<5}` | {domain:<9} | {len(sites):>5} | {cls:<17} | {rec:<29} |")
    lines.append("")

    # Per-glyph site detail
    lines.append("## Per-glyph sites")
    lines.append("")
    for g, (ascii_alias, domain) in TIER2.items():
        lines.append(f"### `{g}` ({ascii_alias}) — {domain}")
        sites = found[g]
        if not sites:
            lines.append("")
            lines.append("_no sites found_")
            lines.append("")
            continue
        lines.append("")
        for file, line, snippet in sites[:30]:  # cap
            snippet = snippet[:160]
            lines.append(f"- `{file}:{line}` — {snippet}")
        if len(sites) > 30:
            lines.append(f"- _... {len(sites) - 30} more sites omitted_")
        lines.append("")

    # Recommendation block
    lines.append("## Apocky-decision block")
    lines.append("")
    unused = [g for g in TIER2 if recommend[g] == "UNUSED"]
    inv_only = [g for g in TIER2 if recommend[g] == "INVENTORY-ONLY"]
    active = [g for g in TIER2 if recommend[g] == "USED"]
    lines.append(f"- UNUSED           ({len(unused)}): {' '.join(unused) if unused else '—'}")
    lines.append(f"- INVENTORY-ONLY   ({len(inv_only)}): {' '.join(inv_only) if inv_only else '—'}")
    lines.append(f"- USED             ({len(active)}): {' '.join(active) if active else '—'}")
    lines.append("")
    lines.append("No spec edits performed by this audit — per T18 non-goal.")
    lines.append("If Apocky approves pruning, remove rows from `specs/12_TOKENIZER.csl`")
    lines.append("master table and regenerate `parser/glyph_aliases.json`.")
    lines.append("")

    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"[OK] audit written to {rel(OUT)}")
    # brief summary (ASCII-only for Windows cp1252 console safety)
    for g, (ascii_alias, domain) in TIER2.items():
        print(f"  {ascii_alias}={recommend[g]:<17}  sites={len(found[g])}  ({domain})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
