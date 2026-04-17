# Contributing to CSLv3

Thanks for considering a contribution. This document covers the dev
workflow + notational conventions + governance rules.

## Dev workflow

1. Fork + branch: `session-N/T<task>-<slug>` (match the session-arc style).
2. Build both toolchains:
   ```sh
   odin build parser/ -out:parser.exe
   cd lsp && cargo build && cd ..
   ```
3. Run the full regression gauntlet:
   ```sh
   for t in tests/test_*.py; do python "$t" || echo "FAIL: $t"; done
   cd lsp && cargo test --test integration && cd ..
   python scripts/check_emit_cert.py
   python scripts/check_solver_versions.py
   ```
4. Commit atomically ; one subtask per commit. Commit messages are
   CSLv3-native where possible (see *Commit style* below).
5. Document any design choice in `parser/DECISIONS.md` with a dated
   entry. Rationale + alternatives-rejected are mandatory.
6. Open a PR ; CI (when available) validates all gates above.

## Commit style

CSLv3-native commit messages. Example:

```
§ T28 : Markdown backend + ruby-annotations

+ parser/emit_markdown.odin ← GFM + anchor auto-gen
+ parser/emit_schema/markdown-v1.md
+ tests/emit_golden/*.md ← 7 goldens

acceptance :
  ✓ pandoc renders without warning
  ✓ round-trip : emit → parse → structural-equiv
```

Sections recommended : context (§), deliverables (+), acceptance (✓).
English is permitted where CSL3 would obscure rather than clarify.

## Notation conventions

All design notes, handoffs, and non-user-facing prose are written in
CSLv3 where possible. User-facing prose (README, error messages,
rustdoc) uses English. See `CLAUDE.md` for the full notational rules.

Key glyphs + aliases for commit messages:

```
§ I> W! R! M? N! Q?   modal / section markers
✓ ◐ ○ ✗ ⊘ △ ▽ ‼      evidence markers
→ ← ↔ ≤ ≥ ≠ ⇒        relations
∧ ∨ ¬ ∀ ∃ ∈ ⊆ ⊂      logical
```

ASCII fallbacks exist for every glyph — see `specs/12_TOKENIZER.csl` for
the full table. Linters accept both ; formatters emit canonical Unicode
unless `--mode=ascii-only` is passed.

## DECISIONS.md protocol

Every non-trivial design choice needs an entry. Template:

```markdown
## YYYY-MM-DD — <short title>

**Decision:** <one-paragraph statement of what was chosen>.

**Why:** <rationale ; include numeric thresholds when applicable>.

**Alternatives rejected:**
- <name> — <reason>
- <name> — <reason>

**Consequence:** <what this enables or constrains going forward>.
```

The log is append-only ; past entries are immutable. Revisions come as
new entries that supersede earlier ones.

## Handoff protocol (for AI-pair sessions)

Long work breaks into `SESSION_N_HANDOFF.csl` files at repo root. Each
documents:

- Status (per-task ✓◐○✗)
- Files new + files modified + files unchanged
- CI matrix state
- Architectural notes applied
- Deferred items
- Open questions for the next session
- Adherence to PRIME_DIRECTIVE invariants

This protocol is optional for single-contributor PRs but required for
multi-session efforts.

## PRIME DIRECTIVE

By contributing you acknowledge the PRIME_DIRECTIVE.md ethical framework
as author-moral intent. No hard requirement ; the MIT license governs
legal terms. Contributions that violate the directive's spirit (harm,
control, manipulation, surveillance, coercion, weaponization) will not
be merged.

## Code of conduct

Treat collaborators — human and AI — as sovereign partners. Disagreement
is welcome ; manipulation is not. See PRIME_DIRECTIVE.md.

## Release cadence

Semver-based. MINOR for feature additions + new schema versions. PATCH
for bug fixes. MAJOR only for breaking changes to stable components per
STABILITY.md. Release-script: `scripts/release_v1.sh` (dry-run by
default ; actual release requires explicit `--do-release` flag).
