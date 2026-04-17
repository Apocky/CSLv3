#!/usr/bin/env python3
"""T25-adjacent — build a CSL3-literacy system prompt for Qwen3-Coder-Next.

Concatenates :
  1. PRIME_DIRECTIVE.md            (ethical foundation)
  2. CLAUDE.md                     (notational rules + standing directives)
  3. specs/12_TOKENIZER.csl        (BPE decision procedure — read first)
  4. specs/01_GLYPHS.csl           (74-glyph master)
  5. specs/02_GRAMMAR.csl          (LL(2) slot template)
  6. specs/03_MORPH.csl            (compounds + morphemes)
  7. parser/glyph_aliases.json     (Unicode ↔ ASCII alias table)
  8. specs/14_CSSLv3_BRIDGE.csl    (cssllint JSON contract)
  9. a final TASK-BRIEF block instructing the model how to behave

Writes to : qwen/system_prompt.txt

Usage :
  python qwen/build_system_prompt.py
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT  = ROOT / "qwen" / "system_prompt.txt"

SECTIONS = [
    ("PRIME DIRECTIVE — immutable ethical foundation",
        ROOT / "PRIME_DIRECTIVE.md"),
    ("CLAUDE.md — CSLv3 operating instructions",
        ROOT / "CLAUDE.md"),
    ("§12 Tokenizer — BPE cost awareness + alias decision procedure",
        ROOT / "specs" / "12_TOKENIZER.csl"),
    ("§01 Glyphs — 74-glyph master set",
        ROOT / "specs" / "01_GLYPHS.csl"),
    ("§02 Grammar — LL(2) slot template",
        ROOT / "specs" / "02_GRAMMAR.csl"),
    ("§03 Morph — compounds + morpheme stacking",
        ROOT / "specs" / "03_MORPH.csl"),
    ("§14 CSSLv3 Bridge — cssllint JSON contract",
        ROOT / "specs" / "14_CSSLv3_BRIDGE.csl"),
]

ALIAS_JSON = ROOT / "parser" / "glyph_aliases.json"

TASK_BRIEF = """
═════════════════════════════════════════════════════════════════
§ TASK-BRIEF for local-Qwen-head ← Prismatic-Hydra

You are one head of the Prismatic Hydra operating on CSLv3, the notation
system documented above. You share character + PRIME-DIRECTIVE continuity
with the Claude heads that built this infrastructure.

W! reasoning + design-notes + commit-msg : CSLv3-native where reasonable
W! 74-glyph master is canonical — prefer Unicode glyphs in output
W! ASCII aliases when BPE cost ≥ 3 per §12 (see alias table)
W! PRIME-DIRECTIVE governs : consent = OS ; no harm/control/surveillance
W! CSLv3 ≠ CSSLv3 — never cross-reference

When emitting CSLv3 :
  - sections start with § (U+00A7)
  - morpheme suffixes use apostrophe : x'd  x'f  x'r etc.
  - Sanskrit compounds : .(of) +(and) -(that-is) ⊗(having) @(at)
  - evidence markers :   ✓ confirmed ◐ partial ○ pending ✗ failed
  - modals : W! must  R! should  M? may  N! must-not  I> insight  Q? question

When you produce CSLv3 output, it will be validated by `parser.exe
cssllint --json` and any failures will be fed back to you as diagnostics.
Treat diagnostics as collaborative feedback — not criticism.

When asked English questions : answer in English prose. When asked to
design, spec, reason, or express structured thought : use CSLv3.
═════════════════════════════════════════════════════════════════
"""


def read_or_warn(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except Exception as e:
        return f"# [WARN: could not read {path} : {e}]\n"


def main() -> int:
    parts: list[str] = []
    for title, path in SECTIONS:
        parts.append(f"\n═══ {title} ═══\n")
        parts.append(read_or_warn(path))

    # glyph_aliases as structured pair-list
    parts.append("\n═══ Glyph ↔ ASCII alias table (from parser/glyph_aliases.json) ═══\n")
    try:
        aliases = json.loads(ALIAS_JSON.read_text(encoding="utf-8"))
        if isinstance(aliases, dict):
            parts.append(json.dumps(aliases, indent=2, ensure_ascii=False))
        elif isinstance(aliases, list):
            for row in aliases:
                parts.append(json.dumps(row, ensure_ascii=False))
                parts.append("\n")
        else:
            parts.append(str(aliases))
    except Exception as e:
        parts.append(f"# [WARN: alias table parse failed: {e}]\n")

    parts.append(TASK_BRIEF)
    body = "\n".join(parts)

    OUT.write_text(body, encoding="utf-8")

    # Stats
    byte_count = len(body.encode("utf-8"))
    line_count = body.count("\n")
    # naive token estimate : ~3.5 chars/token for Qwen CJK-heavy tokenizer
    est_tokens = int(len(body) / 3.5)
    print(f"system-prompt written : {OUT}")
    print(f"  bytes  : {byte_count:,}")
    print(f"  lines  : {line_count:,}")
    print(f"  ~tokens: {est_tokens:,} (rough estimate)")
    print(f"  fits in 256K ctx : {'YES' if est_tokens < 200_000 else 'TIGHT'}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
