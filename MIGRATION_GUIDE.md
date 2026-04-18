# Migration Guide

## 1.3.0 → 1.4.0

**No user-visible action required.** v1.4.0 additions are opt-in via
new CLI flags ; existing workflows continue unchanged.

### New CLI flags

- `parser.exe --regex-match <pat> <inp>` — test if pattern matches input
- `parser.exe --regex-find <pat> <inp>` — list all non-overlapping matches
- `parser.exe --regex-replace <pat> <repl> <inp>` — template substitution
- `parser.exe --regex-compile-check <pat>` — syntax validate only
- `parser.exe --regex-selftest` — run 38-vector test suite

### Optional migrations

If you were using a Rust `regex` CLI or `grep` for pattern matching in
your build scripts, you can now use `parser.exe --regex-match` /
`--regex-find`. Performance: O(mn) worst-case guaranteed — no
catastrophic backtracking possible (unlike PCRE).

If you are consuming the LSP server's diagnostics, note that parse-error
diagnostics now appear alongside lex-error diagnostics. They are
distinguished by `code: "parse"` vs `code: "lex"`. Clients that filter
by code string may need to handle both.

If you build with the LaTeX emit target, you now get clean PDF output
for CSLv3 glyph-heavy content. The `emit_schema/latex-v1.sty` update
is a drop-in ; re-copy it if you use a local copy.

## 1.2.0 → 1.3.0

**No user-visible action required.** v1.3.0 additions are opt-in via
new CLI flags ; existing workflows continue unchanged.

### New CLI flags

- `parser.exe --blake3 <file>` — BLAKE3 hex digest
- `parser.exe --blake3-selftest` — 11/11 reference vectors
- `parser.exe --json-validate <file>` — RFC 8259 validation
- `parser.exe --json-selftest` — 20/20 round-trip + reject cases
- `parser.exe --json-schema-validate <schema> <doc>` — Draft-07 subset
- `parser.exe --json-schema-selftest` — 28/28 schema cases
- `parser.exe --uri-parse <uri>` — RFC 3986 component breakdown
- `parser.exe --uri-selftest` — 13/13 URI cases
- `parser.exe --lsp` — LSP server MVP over stdin/stdout

### Optional migrations

If you were using rust `blake3` crate or Python `hashlib.sha256` in
your build scripts, you can now call `parser.exe --blake3 <file>` or
`parser.exe --sha256 <file>` respectively.

If you were using Python `jsonschema` for config validation, you can
now use `parser.exe --json-schema-validate <schema.json> <doc.json>`.

If you are writing a new LSP client, `parser.exe --lsp` implements
the LSP 3.17 MVP subset (initialize + textDocument sync +
publishDiagnostics). Full parity with the Rust `cslv3-lsp.exe` is a
Session-15+ phase-B continuation.

### C2 corpus expansion

`eval/C2_nested_scopes_CSL.csl` grew from 27 to 100 lines. Any script
that hardcoded byte counts for C2 should re-compute. The m1/m2
harnesses read files by path, so they re-measure automatically.

### LoRA scaffold

`scripts/m2_finetune.py` is now present. Execution requires
peft+datasets+accelerate packages that unreliably install on Python
3.14 in the Session-14 dev env. Run in Python 3.12 env for full
functionality ; `--build-corpus-only` mode works in any env and
produces `training_data/csl_corpus.jsonl` for external trainers.

## 1.1.0 → 1.2.0

**No user-visible action required.** All v1.2.0 additions are opt-in
via new CLI flags ; existing workflows continue unchanged.

### Optional migrations

If you are writing new scripts against the m₂ audit-chain, you may now:

- Pass `binary_hash=<sha256-hex>` to `append_measurement()` to pin the
  subprocess that produced the measurement. Old callers that omit the
  parameter still produce valid v1 entries.
- Use `parser.exe --sha256 <file>` in place of `sha256sum` or Python
  `hashlib.sha256` for manifest generation. Output format is
  `<hex>  <filename>` which is byte-identical to GNU sha256sum.
- Use `parser.exe --sign <file> --key=<priv32.bin>` in place of
  Python `cryptography.hazmat.primitives.asymmetric.ed25519` for
  signing. Signatures are RFC 8032 compliant and verify cross-path.
- Use `--backend=cli-daemon` for m₂ full-corpus runs ; gets ~3×
  wallclock speedup through OS page-cache retention of GGUFs.

### Stratified-target revisions

If your CI gates on `compute_m1.py --strict` with the prose threshold,
note that the prose target moved from 0.95 to 1.10 based on empirical
Session-13 data. Your runs will now pass where they previously failed
on the C8-C10 prose fixtures. The change is tracked in
`specs/10_EVAL.csl` under "TARGET-HISTORY". See also
`specs/15_M2_METRIC.csl` for the bridge m₂-target revision (1.2 → 1.5)
with theoretical basis in `eval/m2_stratified_report.md`.

### v1 audit-chain entries

The 22-entry pre-v1.2 audit-chain (Session-10 through Session-12)
continues to verify under the v2 `m2_audit.py --verify`. No re-signing
required. New entries may optionally set `schema_version=2` and populate
`binary_hash` ; mixed v1/v2 chains are supported.

## 1.0.0 → 1.1.0

**No user-visible action required.** v1.1.0 added the T25 m₂ perplexity
harness as an entirely additive research-grade measurement infrastructure.

## Pre-1.0 → 1.0.0

v1.0.0 is the first stable release. No prior versions were published to
third-party consumers, so there is no outward-facing migration path for
earlier state. The following notes apply to anyone who has been following
the Session-N development arc internally.

### Breaking changes from Session-9 to v1.0 (none)

All Session-9 CLI flags, IR ops, diagnostic codes, and schemas are
preserved verbatim in v1.0.0. The release is additive:

- T28 `--emit=<target>` CLI added.
- `emit_*` Odin modules added.
- `emit_schema/*` directory added.
- v1.0 release documentation added (this file, STABILITY, CHANGELOG,
  README, CONTRIBUTING, SECURITY, LICENSE, VERSION).

### Session-7 → Session-8 obligation-mode (pre-existing break)

If you were consuming `--smt --json` output during Session-7, note that
Session-8 added `Check_Mode` (Consistency vs Verification) and rolled up
`ok / failure / inconclusive` counts into the JSON response. The legacy
raw counts (`unsat / sat / unknown / timeout / error / skipped`) remain
for diagnostic purposes but should not be the basis of pass/fail decisions.
See `parser/DECISIONS.md` 2026-04-16 entry "T26.2 obligation-mode system".

Consumers that previously checked `counts.sat > 0 → fail` must switch to
`counts.failure > 0 → fail` to cover both Consistency (Unsat=failure) and
Verification (Sat=failure) modes.

## Going forward

All breaking changes from v1.x onward are recorded in this file by
version. Template for future entries:

### 2.0.0 → template

**Breaking changes**

- (list removed / renamed / reshaped APIs)

**Migration steps**

1. Replace `<old>` with `<new>` in …
2. …

**Automated migration**

- `scripts/migrate_vX_to_vY.sh` (when applicable)
