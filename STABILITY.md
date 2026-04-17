# Stability Matrix — CSLv3 v1.1.0

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
| m₂ metric (T25)          | experimental  | v1.1.0-introduced ; promotes to stable on acceptance review |
| m₂ harness scripts       | experimental  | `scripts/compute_m2.py` + friends ; additive-only post-v1.0 |
| m₂ audit-chain           | experimental  | `.m2-chain/` Ed25519 JSONL ; shares key-mgmt with T26 |

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
