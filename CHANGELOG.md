# Changelog

All notable changes to CSLv3 are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/). This project adheres
to [Semantic Versioning](https://semver.org/) starting at `1.0.0`.

## [1.1.0] — 2026-04-17

**Released.** Session-12 P1 real-backend validation complete : 21
measurements (3 reference models × 7 corpus files) under the `cli`
backend (llama-perplexity.exe subprocess at D:/llama.cpp/). Aggregate
mean m₂ = 1.210 ± 0.225, range [0.897, 1.668]. 4/7 files cleanly met
stratified-targets ; 3/7 deviations documented in
`eval/m2_stratified_report.md` per handoff §§ WHEN-STUCK clause.
60-measurement comparison harness run committed to
`benchmarks/m2_comparison.md` (real data replacing mock).

All changes remain **additive** under the v1.0 stability commitment.

### Added in 1.1.0 (beyond rc.1)

- **`cli` backend** (`scripts/compute_m2.py`) — third m₂ backend using
  llama-perplexity.exe subprocess. Repeat-pad short fixtures to reach
  2×ctx threshold ; chunk-level NLL with log-PPL bootstrap resampling.
  Python-3.14-compatible without MSVC source-build (fallback when
  llama-cpp-python wheels are unavailable).
- **P1.3 baseline** (`eval/m2_baseline.json`) — first real-backend
  production run replacing the mock-data seed.
- **P1.4 validation report** (`eval/m2_stratified_report.md`) —
  stratified-target verdicts + multi-model agreement analysis.
- **P1.5 comparison data** (`benchmarks/m2_comparison.md`) — 5 topics ×
  4 notations × 3 models = 60 measurements replacing mock table.
- **Grammar-tolerance opt-in** (`parser/lexer.odin`, `parser/parser.odin`)
  — `# @prose-file` / `# corpus-mode: prose-file` directive silences
  lex + parse errors for unknown runes + freeform prose. Fully additive ;
  default parsing unchanged. 5-gate test suite at
  `tests/test_prose_context.py`.

### Changed

- `diag/M2_INTERPRETATION.md` — backend section now documents all three
  backends (`real`, `cli`, `mock`) with tradeoffs. Stratified-target
  table annotated with P1.4 verdicts. Bridge-target revised
  pre-measurement-1.2 → post-measurement-1.5 with theoretical basis.

## [1.1.0-rc.1] — 2026-04-17 (superseded by 1.1.0)

Release candidate for v1.1.0. Infrastructure complete under the mock
backend ; promoted to final 1.1.0 under Session-12 P1.3-P1.5 real-
backend validation. Kept in this log for reproducibility auditors.

## [1.1.0] — 2026-04-17 (original unreleased draft)

**T25 m₂ perplexity harness** — research-grade measurement infrastructure
for empirically validating the *density = sovereignty* claim. All
changes are **additive** under the v1.0 stability commitment ; no
existing APIs, schemas, or CLI flags are modified.

### Added

- **m₂ metric formalization** (`specs/15_M2_METRIC.csl`) — definition,
  stratified-target table per corpus-mode, reproducibility protocol,
  model-set, bootstrap-CI methodology.
- **Core harness** (`scripts/compute_m2.py`) — multi-model dispatch,
  teacher-forced per-token NLL, bootstrap 95% CI (1000 resamples
  default), deterministic seed + temp=0 enforcement, `real` backend via
  `llama-cpp-python` + `mock` backend for CI.
- **Model registry** (`scripts/m2_models.py`, `m2_install_models.sh`) —
  3-model reference set (Qwen2.5-1.5B, Llama-3.2-3B, Mistral-7B-v0.3),
  SHA-256 pinning, download-or-verify, cache-dir at
  `~/.cslv3-m2-models/`.
- **Paraphrase corpus** (`eval/paraphrases/C{1..7}.en` + `README.md`) —
  plain-text EN paraphrases of the seven corpus files, calibrated for
  m₂ comparison (no Markdown syntax tokens polluting the measurement).
- **Paraphrase-quality scorer** (`scripts/m2_quality.py`) — embedding-
  cosine via sentence-transformers with character-5-gram-Jaccard
  fallback, plus entity-recall via identifier-extraction + stemming.
  Backend-aware thresholds.
- **Signed audit-chain** (`scripts/m2_audit.py`) — Python-native
  Ed25519 (via `cryptography`), JSONL append-only log at
  `.m2-chain/runs.jsonl`, per-entry signatures verify the complete
  chain. Genesis entry seeds the chain.
- **HTML visualizer** (`scripts/m2_visualize.py`) — summary table +
  stratified-target banner + per-token NLL heatmap + side-by-side
  CSL/EN rendering.
- **Comparison harness** (`scripts/m2_compare.py`) — CSLv3 vs APL/J/k
  vs Lojban vs English-prose on 5 algorithm reference passages. Notes
  the LLM-unfamiliarity caveat prominently.
- **Tests** (`tests/test_m2_harness.py`, `tests/test_m2_audit.py`,
  `tests/m2_fixtures/`) — 8-gate harness suite, 6-gate audit suite,
  all green without real-model weights (mock backend).
- **Interpretation doc** (`diag/M2_INTERPRETATION.md`) — how to read m₂,
  common misreadings, reproducibility anchors.
- **Benchmarks** (`benchmarks/m2_throughput.md`,
  `benchmarks/m2_comparison.md`) — mock-backend throughput table +
  CSL vs APL/Lojban/prose density comparison.
- **Spec index update** (`specs/INDEX.csl`) — §15 added.

### Changed

- `STABILITY.md` — new section lists T25 components as v1.1.0-tracked.
- `VERSION` — bumped 1.0.0 → 1.1.0.

### Non-breaking

- No existing CLI flags modified.
- No existing JSON schemas modified.
- No existing diagnostic codes renumbered.
- No removal of any v1.0 public surface.
- v1.0 test matrix (17 gates) remains green.

### Notes

- m₂ is a *relative* measurement ; pre-trained LLMs will always score
  English more predictable than CSL due to training-corpus bias.
  m₂ ≈ 1.0-1.5 is the expected target range, not 1.0.
- The audit-chain Ed25519 key in `.m2-chain/keys/` is a dev-stub.
  Production deployments should replace it with an organization-signed
  root before publishing signed measurements.

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
