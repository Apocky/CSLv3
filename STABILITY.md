# Stability Matrix — CSLv3 v1.5.0

Post-v1.0 contract: components marked **stable** require a MAJOR version
bump for breaking changes. Components marked **experimental** may change
within a MINOR bump with deprecation notice.

## Components

| Component                | Stability     | Notes                                          |
|--------------------------|---------------|------------------------------------------------|
| parser                   | stable        | LL(2) over 74-glyph master (spec §02)          |
| tokenizer                | stable        | Dual-glyph Unicode + ASCII alias (spec §12)    |
| grammar                  | stable        | Self-grammar in `specs/13_GRAMMAR_SELF.csl`    |
| types (T20)              | stable        | HM + row-poly + refinement + dependent-kinds   |
| IR (T21)                 | stable        | SSA + structured regions ; 40 op-name consts   |
| ir-verifier (T21)        | stable        | 5-class invariants ; CSL-E-3xx codes           |
| SMT integration (T26)    | stable        | Z3 ≥ 4.13 + CVC5 ≥ 1.1 ; two-mode obligations  |
| proof-cache (T26)        | stable        | SHA-256 sharded content-addr                    |
| audit-chain (T26)        | stable        | Ed25519-signed JSONL ; replay-verifiable        |
| opt-passes (T27)         | stable        | 6 passes × 4 levels ; pass-manager             |
| LSP v3.17 (T24)          | stable        | 17 methods ; VSCode client                     |
| emit-mir (T28.1)         | stable        | `mir-v1` schema ; CSSLv3-MIR dialect           |
| emit-markdown (T28.2)    | stable        | `markdown-v1` ; GFM-compliant                  |
| emit-html (T28.3)        | stable        | `html-v1` CSS taxonomy                         |
| emit-latex (T28.4)       | experimental  | `latex-v1` ; requires `latexmk`/XeLaTeX        |
| emit-json (T28.5)        | stable        | `json-v1` unified schema                       |
| cssllint JSON            | stable        | Contract frozen in `specs/14_CSSLv3_BRIDGE.csl`|
| m₂ metric (T25)          | experimental  | v1.1.0-introduced ; 21-measurement real-backend baseline recorded ; promotes to stable in v1.2 |
| m₂ harness scripts       | experimental  | `scripts/compute_m2.py` + friends ; additive-only post-v1.0 |
| m₂ `cli` backend         | experimental  | Session-12 addition ; repeat-pad llama-perplexity subprocess ; ratio-unbiased ; absolute-NLL biased |
| m₂ audit-chain           | experimental  | `.m2-chain/` Ed25519 JSONL ; shares key-mgmt with T26 |
| prose-file directive     | experimental  | `# @prose-file` opt-in ; Session-12 P2.2 ; silences lex+parse errors for freeform fixtures |
| prose corpus (C8-C10)    | stable        | Session-13 ; three prose-mode fixtures + paraphrases + m₁/m₂ baselines |
| SHA-256 Odin (T2)        | stable        | `parser/sha256.odin` FIPS 180-4 ; 4/4 NIST vectors ; `--sha256` CLI |
| SHA-512 Odin             | stable        | `parser/sha512.odin` FIPS 180-4 ; internal dep of Ed25519 |
| Ed25519 signer/verifier  | stable        | `parser/ed25519.odin` wraps Odin `core:crypto/ed25519` ; RFC 8032 compliant ; `--sign` / `--verify` CLI |
| Levenshtein Odin         | stable        | `parser/levenshtein.odin` Wagner-Fischer ; `--distance` CLI |
| audit-chain schema v2    | stable        | `binary_hash` + `schema_version` fields ; v1 entries verify byte-identical |
| cli-daemon backend       | experimental  | `scripts/compute_m2.py --backend=cli-daemon` ; mmap-retained GGUF |
| BLAKE3 Odin              | stable        | `parser/blake3.odin` reference v0.3.7 ; 11/11 test vectors ; `--blake3` CLI |
| JSON parser+emitter Odin | stable        | `parser/json_codec.odin` RFC 8259 ; 20/20 round-trip ; `--json-validate` CLI |
| JSON-Schema Odin         | experimental  | `parser/json_schema.odin` Draft-07 subset ; 28/28 vectors ; pattern awaits A8 regex |
| URI parser Odin          | stable        | `parser/uri.odin` RFC 3986 ; 13/13 vectors ; ASCII host only (IDNA deferred) |
| LSP server Odin          | experimental  | `parser/lsp_server.odin` MVP ; initialize + didOpen/Change/Close + publishDiagnostics (lex+parse) |
| Regex engine Odin        | stable        | `parser/regex*.odin` Pike-VM ; 38/38 selftest ; Unicode \p{L/N/P/S} ; `--regex-*` CLI |
| JSON-Schema pattern      | stable        | Draft-07 `pattern` keyword wired to regex (Session-15 O1) ; 34/34 schema selftest |
| LaTeX glyph coverage     | stable        | `emit_schema/latex-v1.sty` newunicodechar for 40+ glyphs ; 7/7 PDFs warning-free |
| LoRA fine-tune pipeline  | stable        | `scripts/m2_finetune.py` + `scripts/m2_finetune_measure.py` ; isolation-experiment scaffold |
| LoRA isolation result    | research      | Session-16 data : CSL-only adapter confirms H1+H2 on Qwen2.5-1.5B ; see `diag/M2_FINETUNE_INTERPRETATION.md` |

## Diagnostic code namespace (frozen)

- **CSL-E/W/I-0xx** — parser (morph / slot / evidence / compound / permissive)
- **CSL-E/W/I-1xx** — lexer + parser structural errors (reserved)
- **CSL-E/W/I-2xx** — type-checker (T20)
- **CSL-E/W/I-3xx** — IR verifier (T21)
- **CSL-E/W/I-4xx** — SMT discharge (T26)
- **CSL-E/W/I-5xx** — opt-pass diagnostics (T27)
- **CSL-E/W/I-6xx** — emit (T28)
- **CSL-I-7xx** — m₂ metric harness (T25, v1.1.0) — reserved; no codes emitted yet

Any new code added within a namespace is a MINOR change. Renumbering
existing codes within a namespace is a MAJOR change.

## Schema versions (independent semver)

Emit target schemas track their own versions independently of the parser:

- `mir-v1` — current
- `markdown-v1` — current
- `html-v1` — current
- `latex-v1` — current (experimental)
- `json-v1` — current

Future schema revisions add a digit (e.g. `mir-v2`) and coexist via the
`schemaVersion` field in emitted output.

## Solver version pins

- Z3 ≥ 4.13.0 (verified on 4.16.0)
- CVC5 ≥ 1.1.0 (verified on 1.3.3)

Older solvers may work but are unsupported. `scripts/check_solver_versions.py`
enforces the floor.

## Breaking-change policy

Post-v1.0, any of the following constitute breaking changes requiring a
MAJOR bump:

1. Removing a stable-component public API (CLI flag, Odin proc, JSON key).
2. Changing serialized schema semantics without a version bump.
3. Changing a stable diagnostic code number.
4. Changing IR op-name constants.
5. Changing the cssllint JSON contract in `specs/14`.

Non-breaking (MINOR) changes:

1. Adding new CLI flags, IR ops, diagnostic codes within namespaces.
2. Adding new opt-passes or schema fields with defaults.
3. Performance improvements.
4. New emit targets.
5. Bug fixes that don't alter documented contracts.

See `MIGRATION_GUIDE.md` for per-release migration notes going forward.

## Replacement policy (drop-in discipline)

Bespoke replacements of external dependencies (`diag/DEPENDENCY_ELIMINATION_ROADMAP.md`)
must satisfy:

1. **Byte-equivalent output** — SHA-256 of manifest bytes, emit-target
   binaries, audit-chain signatures must match the replaced path
   byte-for-byte before the replacement is promoted from experimental
   to stable.
2. **Drop-in call-site** — callers change at most one line (binary path
   or import). No user-visible CLI surface change.
3. **Backward-compat verify** — any replacement of a path that consumes
   previously-persisted artifacts (e.g. audit-chain entries) must
   verify all pre-replacement artifacts under the new tool.
4. **Selftest gate** — each bespoke module includes a `--X-selftest`
   flag or equivalent that runs published standard test-vectors
   (NIST / RFC / IETF). CI must run all selftests every release.
5. **Spec-cite in source** — header comment of each bespoke file names
   the authoritative reference (FIPS 180-4, RFC 8032, etc.) so
   future maintainers can audit correctness against standard.
6. **Stable bump discipline** — bespoke additions start experimental
   for exactly one MINOR release cycle, then promote to stable upon
   at-least-one-release's byte-equivalence verification.

First bespoke batch (v1.2.0): SHA-256, SHA-512, Ed25519 (via stdlib),
Levenshtein. Bespoke BLAKE3, JSON, URI, Regex deferred to v1.3+.
