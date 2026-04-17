# Migration Guide

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
