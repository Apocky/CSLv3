# Changelog

All notable changes to CSLv3 are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/). This project adheres
to [Semantic Versioning](https://semver.org/) starting at `1.0.0`.

## [1.0.0] — 2026-04-16

First stable release. This consolidates the complete 10-session arc from
parser-bootstrap through language-server + multi-target code emission.
Breaking changes after this version require a MAJOR bump.

### Added

- **Parser + tokenizer + grammar** (Sessions 1–3)
  - LL(2) parser for the 74-glyph master set ; round-trip-safe pprint.
  - Tokenizer with dual-glyph Unicode + ASCII-alias tables.
  - Error-recovery with forward-progress guards (40/40 fixture coverage).
  - Severity modes: `--lint` / default / `--strict` / `--strict-parse`.
  - Permissive-accept tracking (CSL-W-007) with promotion-under-strict.
- **Comment round-trip** (Session 5, T23)
  - Comments preserved at AST-shape + position across 5 pprint modes.
- **HM type-checker** (Session 5, T20)
  - Bidirectional HM + Leijen row-polymorphism + refinement types.
  - Morpheme-tag mapping (`'d 'f 's 't 'e 'm 'p 'g 'r`).
  - Dependent kinds stubbed (Pi/Sigma declared ; full NbE deferred).
- **Permissive-accept gap closure** (Session 5, T22)
  - All 5 Session-4 gaps promoted to semantic-detect with pragma meta.
- **SSA+regions IR** (Session 6, T21)
  - MLIR-style Op/Region/Block/Value ; Braun-style on-the-fly SSA.
  - 40 op-name constants ; 15+ expression-kind lowerers.
  - 5-class verifier (shape/term/dominance/types/dangling) with 7
    CSL-E-3xx diagnostic codes.
  - `--ir` / `--ir --json` / `--ir --verify` / `--ir-selftest` CLI.
- **SMT integration** (Session 7, T26)
  - Formula AST + SMT-LIB2 emitter with deterministic sorted-key output.
  - Z3 + CVC5 stdio drivers via tempfile ; graceful-degrade on missing.
  - SHA-256 proof-cache ; Ed25519-signed JSONL audit-chain.
  - 9-morpheme UF encoding (durative → duration(v)>0 etc.).
  - `--smt` / `--smt --json` / `--smt-selftest` / `--smt-audit-verify`.
- **T26 validation closure** (Session 8, T26.1–.3)
  - Real Z3 + CVC5 installed via GitHub-release no-admin path.
  - 6/6 smt_good discharge Sat (Consistency-mode) — semantic fix.
  - 15/15 smt_bad discharge Sat counter-example ; × 2 solvers = 30 trials.
  - Audit-chain 10 signed entries verified via `--smt-audit-verify`.
  - Throughput: Z3 122.8 / CVC5 137.3 cached ops/s.
- **IR-opt passes** (Session 8, T27)
  - Pass-manager with requires/preserves analysis-invalidation.
  - 6 passes: const-fold / dce / cse / inline / partial-eval / smt-prune.
  - 4 opt-levels (O0/O1/O2/O3) + `--opt=custom --passes=…` + `--stats`.
  - 28 golden IR-dumps (7 corpus × 4 levels). O0–O2 byte-stable.
- **LSP prototype** (Session 9, T24)
  - Rust tower-lsp server (2227 LOC) + VSCode TypeScript extension (457 LOC).
  - 17 LSP v3.17 methods: hover / completion / formatting / goto /
    references / documentSymbol / codeAction / codeLens / semanticTokens.
  - `parser.exe` subprocess driver with BLAKE3-keyed 4-way cache.
  - Latencies: cold-open <80ms ; didChange ≤300ms ; hover <1ms.
  - `cargo clippy -D warnings` clean ; 4/4 integration tests pass.
- **Multi-target codegen** (Session 10, T28)
  - 5 emit targets: MIR (CSSLv3 dialect) / Markdown / HTML / LaTeX / JSON.
  - `--emit=X` / `--out=` / `--sign` / `--incremental` / `--schema`.
  - Cert-signing reuses Ed25519 audit-chain infrastructure.
  - Incremental emit cache in `.emit-cache/` (sharded).
  - 35 goldens committed (7 corpus × 5 targets).
  - Schemas published under `parser/emit_schema/`.

### Changed

- **Session 8:** Obligation two-mode system (Consistency vs Verification)
  replaces Session-7's unconditional `assert ¬φ` encoding. Morpheme-binding
  obligations are self-declared refinements → Sat=success ; div/bounds
  obligations are proof-obligations → Unsat=success. Exit-code uses
  mode-classified `ok / failure / inconclusive` counts.
- **Session 5:** `emit_comments = true` became the lexer default so comments
  thread through the round-trip invariant without opt-in.

### Security

- PRIME_DIRECTIVE.md committed at repo root. Consent-as-OS framework is
  author-moral intent, not a license term.
- Ed25519 dev-stub keys live in `.proof/keys/` ; production deployments
  must replace with organization-signed roots.

### Stability

See `STABILITY.md` for the per-component stability matrix. All core
components except `emit-latex` (experimental) are stable and subject to
the post-v1.0 semver contract.

## Pre-1.0 development log

Sessions 1–10 are consolidated into the 1.0.0 entry above. Per-session
detail lives in `SESSION_N_HANDOFF.csl` (N=1..10) files + `parser/DECISIONS.md`.
