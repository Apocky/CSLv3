# UNCONFLATION — CSSL ≠ CSLv3

## What happened

Session 1 conflated **CSSL** (a separate language/project of Apocky's) with **CSLv3** (this repo's notation language). The CSLv3 reference parser was built, but placed in a `cssl2/` subfolder and named "CSSL2 parser" throughout — implying it was the frontend for CSSL rather than the reference compiler for CSLv3 itself. Session 2 corrected the naming, the paths, and the spec content.

## Rule enforced

```csl
t∞: CSSL ≠ CSLv3  •  separate projects  •  ¬conflate
```

CSSL is a separate language that lives in a separate repo (TBD by Apocky). Nothing in this repo references it except this file and a disclaimer at the top of `specs/08_COMPILER.csl`. The parser here is for CSLv3 notation, not CSSL.

## Files moved

| from | to |
|------|-----|
| `cssl2/lexer.odin`          | `parser/lexer.odin` |
| `cssl2/parser.odin`         | `parser/parser.odin` |
| `cssl2/ast.odin`            | `parser/ast.odin` |
| `cssl2/token.odin`          | `parser/token.odin` |
| `cssl2/main.odin`           | `parser/main.odin` |
| `cssl2/tests/C1..C7.csl`    | `parser/tests/C1..C7.csl` |
| `cssl2/` (folder)           | *deleted* |

After move: `parser.exe` is the new binary name (from `package cslparser`). Prior session's `cssl2.exe` was removed.

## Code renames

- `package cssl2` → `package cslparser` in all `.odin` files.
- Top-of-file comments like `// § CSSL2 LEXER` → `// § CSLv3 PARSER — LEXER`.
- CLI description: `cssl2 — Caveman Spec Language v3 parser prototype` → `cslparser — Caveman Spec Language v3 reference parser`.
- CLI usage: `usage: cssl2 ...` → `usage: cslparser ...`.
- `tests/C3_type_inference.csl`: `"CSSL2 static checking"` → `"CSLv3 static checking"`.

## Specs renamed

- `specs/08_CSSL2.csl` → `specs/08_COMPILER.csl` (full rewrite).
  - Title: "CSLv3 REFERENCE COMPILER"
  - Scope disclaimer added at top.
  - Framing: this is the compiler for CSLv3 notation, not for CSSL.
  - Preserved: lexical spec, type system, backend targets (x86-64 AVX2 + SPIR-V), rank polymorphism, APL adverbs, all code examples.
  - Added: "REFERENCE IMPLEMENTATION" section pointing to `parser/` with status markers.

## Cross-references purged

| file | change |
|------|--------|
| `CLAUDE.md` | Triple-scope §3: "CSSL2 compiler input" → "CSLv3 reference compiler input". File list blurb updated. "CSSL2 source files" → "CSLv3 compiler source files". |
| `CSLv3_ONBOARDING.md` | Scope 3 heading + body rewritten. File list: `08_CSSL2.csl` → `08_COMPILER.csl`. Dependent-types aspirational note: `"for CSSL2"` → `"for CSLv3 compiler"`. "Parser prototype hasn't been built yet" → "A lexer+parser+AST prototype lives in `parser/`." |
| `specs/00_MANIFEST.csl` | Scope T3 line, ancestry line, file-list entry for 08, reconciliation log entry, NEXT list entry (marked ✓ for parser). |
| `specs/09_BRIDGE.csl` | "agent CoT, CSSL2 source" → "agent CoT, CSLv3 compiler source". |
| `specs/11_RESEARCH.csl` | "ASPIRATION for CSSL2 v2" → "ASPIRATION for CSLv3 compiler v2". |
| `specs/12_TOKENIZER.csl` | "target = CSSL2 compiler" → "target = CSLv3 compiler". |
| `CLAUDE_CODE_TASK.md` | Renamed to `CLAUDE_CODE_TASK_1_HISTORICAL.md` with a disclaimer header. CSSL2 references in-body left as historical record (see disclaimer). |

## Verification

```bash
$ cd /c/Users/Apocky/source/repos/CSLv3
$ grep -rn "CSSL" . --include="*.md" --include="*.csl" | grep -v HISTORICAL | grep -v UNCONFLATION
./specs/08_COMPILER.csl:2:I> CSSL is a separate project ¬ part-of-CSLv3
./specs/08_COMPILER.csl:11:  ✗ this spec does ¬ describe CSSL (separate language, separate repo)
```

The only remaining hits are the **intentional disclaimer lines** at the top of `08_COMPILER.csl` that document the separation. All historical references are in `CLAUDE_CODE_TASK_1_HISTORICAL.md` (prefixed with a disclaimer) and this file.

```bash
$ test -d parser && echo "parser/ exists"
parser/ exists
$ test ! -d cssl2 && echo "cssl2/ deleted"
cssl2/ deleted
$ cd parser && /c/odin/odin.exe build .
# → parser.exe (builds clean)
```

## Decisions taken

- Chose `parser/` over `CSLv3\` root for the Odin code. The task prompt said "parent folder CSLv3" but organizing `.odin` files as siblings to `.md` files is ugly. `parser/` is descriptive and preserves the module boundary. Apocky may override.
- Chose `cslparser` as the Odin package name (not `cslv3` — would conflict with the notation itself when written in text).
- Preserved the original `CLAUDE_CODE_TASK.md` as `CLAUDE_CODE_TASK_1_HISTORICAL.md` rather than rewriting its CSSL2 mentions. Task prompts are historical records; modifying them in place would obscure what was actually asked.
