# CSLv3 — Caveman Spec Language v3

An ultra-dense specification notation designed for **three-way** readability:
human spec authors, AI reasoning substrates, and compiler frontends.
Unicode-rich, ASCII-aliased, LL(2)-parseable.

> **v1.0.0 — 2026-04-16.** Ten sessions. Parser → type-checker → IR →
> SMT → optimizer → LSP → multi-target codegen. [CHANGELOG.md](CHANGELOG.md)
> has the per-session log ; [STABILITY.md](STABILITY.md) the support contract.

## Why CSLv3

*density = sovereignty.* Every glyph earns its place. 74 Unicode glyphs +
ASCII aliases let a spec remain legible to humans, parseable by compilers,
and cheap for LLM tokenizers. Morphemes (`'d 'f 's 't 'e 'm 'p 'g 'r`) carry
refinement types inline ; Sanskrit compounds (`. + - ⊗ @`) express
nominal/possessive/locative composition without new keywords. See
`specs/` for the 14-file specification suite.

## Install

```sh
git clone <this-repo> CSLv3
cd CSLv3

# Parser (Odin)
odin build parser/ -out:parser.exe

# Language server (Rust)
cd lsp && cargo build --release && cd ..

# SMT solvers (optional — required for --smt discharge)
powershell scripts/install_solvers.ps1
```

## Quick start

```sh
# Parse + pretty-print a spec file
./parser.exe parser/tests/C1_sort.csl

# Type-check with diagnostics
./parser.exe --typecheck --json parser/tests/C1_sort.csl

# Emit IR at opt-level 2 with pass-statistics
./parser.exe --ir --opt=O2 --stats parser/tests/C1_sort.csl

# SMT-discharge refinement obligations (requires Z3 or CVC5)
./parser.exe --smt --json --z3=<path> parser/tests/C1_sort.csl

# Emit to 5 target formats
./parser.exe --emit=json     my_spec.csl        # canonical unified JSON
./parser.exe --emit=markdown my_spec.csl        # GitHub-Flavored Markdown
./parser.exe --emit=html     my_spec.csl        # semantic HTML5
./parser.exe --emit=latex    my_spec.csl        # article-class LaTeX
./parser.exe --emit=mir      my_spec.csl        # CSSLv3-MIR dialect
```

## Feature matrix

| Layer                  | Files                        | Acceptance                    |
|------------------------|------------------------------|-------------------------------|
| Parser + tokenizer     | `parser/*.odin` (30+ files)  | 40/40 error-recovery fixtures |
| Type-checker           | `parser/{types,infer,refine,unify}.odin` | 25 good + 14 bad + 14 corpus |
| IR (SSA + regions)     | `parser/ir*.odin + lower.odin` | 7/7 corpus clean ; 5/5 selftest |
| SMT                    | `parser/smt*.odin`           | 10/10 selftest + 30 solver trials |
| Opt-passes             | `parser/pass.odin + opt_*.odin + analysis.odin` | 6 passes × 4 levels |
| LSP v3.17              | `lsp/server/src/*.rs`        | 17 methods + 4/4 cargo tests |
| VSCode extension       | `lsp/editors/vscode/`        | TypeScript strict + TextMate |
| Codegen (5 targets)    | `parser/emit*.odin`          | 35 goldens + cert-chain       |

## CLI cheatsheet

```
parser.exe [MODE] [OPTIONS] <file>

MODES
  (default)         AST S-expression dump
  --tokens          tokenizer stream
  --errors          errors-only report
  --semantic        permissive + morpheme checks
  --print           canonical pprint
  --roundtrip       parse → print → reparse → compare
  --typecheck       HM + refinements
  --ir              lower to SSA + regions
  --smt             discharge obligations (needs solver)
  --emit=<target>   codegen (json|markdown|html|latex|mir)
  cssllint          machine-readable diagnostics (positional subcommand)

OPTIONS
  --json            machine-readable output
  --strict          warnings → errors
  --strict-parse    promote PERMISSIVE_ACCEPT to error
  --lint            warnings only ; rc=0
  --mode=<style>    canonical|compact|literate|ascii-only|unicode-only
  --opt=O0..O3      opt-pipeline level (with --ir)
  --sign            sign emit output via Ed25519 audit-chain
  --incremental     consult emit-cache for stable content
  --out=<path>      write to file (cert + map sidecars when applicable)
```

## Documentation layout

```
specs/                spec suite (14 files) — read §§00 first
parser/DECISIONS.md   rolling design-decision log
SESSION_N_HANDOFF.csl session-transition context (N=1..10)
PRIME_DIRECTIVE.md    ethical foundation (author-moral intent)
STABILITY.md          v1.0 stability matrix + semver policy
MIGRATION_GUIDE.md    version-to-version migration notes
CHANGELOG.md          per-release change log
CONTRIBUTING.md       dev workflow + CSLv3-native commit style
SECURITY.md           vulnerability disclosure
```

## License

MIT — see [LICENSE](LICENSE). The PRIME_DIRECTIVE.md framework is
author-moral intent, not a license term.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Commit messages and design notes
should be CSLv3-native where possible (the notation scales to prose
surprisingly well).

## Provenance

Ten sessions of collaborative development between Apocky and Claude Opus
4.7-1M (the Prismatic Hydra). Each session's handoff file documents the
scope, design decisions, and hand-off context to the next head. The
project is a self-referential case study: CSLv3 was used throughout the
design process to reason about itself.
