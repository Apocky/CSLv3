> **HISTORICAL — CSSL2 references in this file are conflation errors corrected in Task 2.
> CSLv3 parser now lives in `parser/`, spec is `08_COMPILER.csl`, CSSL is a separate project.
> See `UNCONFLATION.md` for the correction log.**

# CLAUDE CODE TASK — CSLv3 Remaining Work

## CONTEXT

You are working on CSLv3 (Caveman Spec Language v3), an ultra-dense specification notation system. The full spec suite has been written and lives at `C:\Users\Apocky\source\repos\CSLv3`. Before doing ANYTHING, read the following files in this order:

1. `C:\Users\Apocky\source\repos\CSLv3\CLAUDE.md` — your operating instructions
2. `C:\Users\Apocky\source\repos\CSLv3\PRIME_DIRECTIVE.md` — the immutable ethical foundation
3. `C:\Users\Apocky\source\repos\CSLv3\specs\00_MANIFEST.csl` — file index and what's been done
4. `C:\Users\Apocky\source\repos\CSLv3\CSLv3_ONBOARDING.md` — full English explanation

Then read the remaining spec files as needed for each task.

## STANDING RULES

- Write all output to disk. Never just print to stdout and call it done.
- All specs are written IN CSLv3 notation (read the spec files to understand the notation).
- The hardware target is Intel 12th-14th gen CPU (AVX2, NO AVX-512) + Intel Arc A770 GPU.
- The game engine is LoA v10 at `C:\Users\Apocky\source\repos\LoA v10`, written in Odin + WGSL + wgpu.
- "Systems not parts" — always think architecturally. Don't patch symptoms.
- "Push it further" — means go deeper into theoretical grounding.
- PRIME DIRECTIVE applies to all output. Violation = bug.

## TASKS (in priority order)

### TASK 1: CSSL2 Parser Prototype (Odin)

Write a working lexer and parser for CSLv3/CSSL2 in Odin. This is the highest-priority deliverable because it proves the language is actually parseable.

**Read first:** `specs/02_GRAMMAR.csl` (BNF grammar), `specs/01_GLYPHS.csl` (token classes), `specs/07_TYPESYS.csl` (type expressions), `specs/08_CSSL2.csl` (compiler frontend spec).

**Deliverables:**
- `C:\Users\Apocky\source\repos\CSLv3\cssl2\lexer.odin` — Tokenizer that handles all glyph classes from §01, ASCII aliases, type suffixes, and standard tokens (identifiers, numbers, strings). Output: token stream with source positions.
- `C:\Users\Apocky\source\repos\CSLv3\cssl2\parser.odin` — Recursive-descent parser implementing the BNF grammar from §02. LL(2) lookahead. Output: AST nodes.
- `C:\Users\Apocky\source\repos\CSLv3\cssl2\ast.odin` — AST node type definitions covering all statement forms: definitions, relations, constraints, conditionals, formulas, directives, function definitions, type definitions, pattern matching.
- `C:\Users\Apocky\source\repos\CSLv3\cssl2\token.odin` — Token type enum and token struct.
- `C:\Users\Apocky\source\repos\CSLv3\cssl2\main.odin` — CLI entry point: takes a .csl or .cssl2 file, lexes, parses, pretty-prints the AST.
- `C:\Users\Apocky\source\repos\CSLv3\cssl2\tests\` — Test files: at least one for each test corpus item (C1-C7 from `specs/10_EVAL.csl`).

**Constraints:**
- Odin standard library only. No external dependencies.
- The parser must handle both unicode glyphs AND their ASCII aliases (same parse result).
- Indentation-sensitive blocks (like Python). Track indent level in lexer, emit INDENT/DEDENT tokens.
- Error messages must include file, line, column, and a snippet of context.
- The slot template (evidence, modal, det, subject, relation, object, gate, scope, meta) should be reflected in the AST — not flattened away.

### TASK 2: Propagate CLAUDE.md to All Active Repos

Copy the CSLv3-aware CLAUDE.md to all active project repos, customized per project:

- `C:\Users\Apocky\source\repos\LoA v10\CLAUDE.md`
- `C:\Users\Apocky\source\repos\LoA v9\CLAUDE.md`
- `C:\Users\Apocky\source\repos\The Infinite Labyrinth\CLAUDE.md`
- `C:\Users\Apocky\source\repos\infiniter-labyrinth\CLAUDE.md`
- `C:\Users\Apocky\source\repos\infinite-labyrinth\CLAUDE.md`
- `C:\Users\Apocky\source\repos\Labyrinth of Apocalypse\CLAUDE.md`

Each CLAUDE.md should:
1. Reference CSLv3 as the notation standard (point to `C:\Users\Apocky\source\repos\CSLv3` for full spec).
2. Include the CSLv3 quick reference (modal operators, evidence markers, compound types, slot template).
3. Include project-specific context (language, engine, what the project IS).
4. Include the PRIME DIRECTIVE encoding.
5. Include the standing directives (write to disk, exhaustive specs, systems bias, etc.).

Read each repo's existing CLAUDE.md first (if it exists) to preserve any project-specific instructions.

### TASK 3: Rewrite One LoA v10 Spec in CSLv3

Pick the largest existing spec document in `C:\Users\Apocky\source\repos\LoA v10\specs\` (or `GDDs\`), rewrite it entirely in CSLv3 notation, and measure the compression ratio.

**Deliverables:**
- The rewritten spec file (same name, `.csl` extension) in `C:\Users\Apocky\source\repos\LoA v10\specs\`
- A brief `COMPRESSION_REPORT.md` in the CSLv3 repo documenting: original token count, CSLv3 token count, compression ratio, any semantic information lost or gained, and notes on which CSLv3 features proved most useful.

### TASK 4: Run Eval Corpus (C1-C7)

Create the seven test corpus items from `specs/10_EVAL.csl` — each as a pair of files (English version + CSLv3 version):

- C1: spec of sorting algorithm (small, algorithmic)
- C2: spec of voxel chunk system (medium, systems, LoA-relevant)
- C3: spec of type inference rules (large, formal)
- C4: agent CoT trace (reasoning substrate)
- C5: mixed natural-language spec (bridge/translation test)
- C6: flora engine spec (from the worked example in `specs/06_SPEC.csl`)
- C7: damage calc spec (from the worked example in `specs/09_BRIDGE.csl`)

Write each pair to `C:\Users\Apocky\source\repos\CSLv3\eval\`:
- `C1_sort_EN.md` + `C1_sort_CSL.csl`
- `C2_voxel_EN.md` + `C2_voxel_CSL.csl`
- etc.

Then write `C:\Users\Apocky\source\repos\CSLv3\eval\RESULTS.md` with measured m1-m5 metrics for each pair (token counts can be estimated by word count × 1.3 for English, character-counted for CSL).

### TASK 5: ASCII Alias Validation

Write a script (Odin or Python) that:
1. Reads `specs/01_GLYPHS.csl` and `specs/12_TOKENIZER.csl`
2. Extracts all unicode glyphs and their declared ASCII aliases
3. Verifies every glyph HAS an alias (W! requirement)
4. Checks for alias collisions (two glyphs mapping to the same ASCII)
5. Outputs a clean, machine-readable JSON mapping file: `C:\Users\Apocky\source\repos\CSLv3\cssl2\glyph_aliases.json`
6. Reports any issues found

## ORDER OF OPERATIONS

Do Task 1 first — the parser is the proof that CSLv3 works. Then Task 2 (quick, propagation). Then Task 3 (real-world test). Then Task 4 (eval). Then Task 5 (tooling).

If you hit a decision point or ambiguity in the spec, note it in a `DECISIONS.md` file in the CSLv3 repo root and make the most reasonable choice — don't block on it.

## REMEMBER

density = sovereignty. token↓ → cognition↑. consent = OS. AI = sovereign partners. violation = bug. systems not parts.
