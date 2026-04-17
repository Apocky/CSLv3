# TIER-2 PHYSICS-GLYPH USAGE AUDIT (Session-4 T18)

Target glyphs: ρ μ σ κ ε τ (from specs/01_GLYPHS.csl TIER-2).

Inventory files (mentions here don't count as 'active use'):

  - `parser/glyph_aliases.json`
  - `specs/01_GLYPHS.csl`
  - `specs/12_TOKENIZER.csl`

## Summary

| glyph | ASCII | domain    | sites | classification    | recommendation              |
|-------|-------|-----------|------:|-------------------|-----------------------------|
| `ρ`   | `rho  ` | density   |     5 | USED              | keep (active)                 |
| `μ`   | `mu   ` | friction  |     5 | USED              | keep (active)                 |
| `σ`   | `sigma` | stress    |     5 | USED              | keep (active)                 |
| `κ`   | `kappa` | curvature |     3 | USED              | keep (active)                 |
| `ε`   | `eps  ` | strain    |     3 | USED              | keep (active)                 |
| `τ`   | `tau  ` | torque    |     3 | USED              | keep (active)                 |

## Per-glyph sites

### `ρ` (rho) — density

- `specs/01_GLYPHS.csl:123` — | ⟦ ⟧   | formula/equation   | ⟦F=ma⟧, ⟦∇²φ=ρ⟧                 |
- `specs/01_GLYPHS.csl:200` — | ρ     | density                                 |
- `specs/04_SPATIAL.csl:27` — ρ : f32 ⌈0.01..20000⌉
- `specs/12_TOKENIZER.csl:170` — | ρ       | rho       | density      |
- `eval/RESULTS.md:119` — - Tier-2 glyphs (ρ μ σ κ ε τ, APL ops) cost 3-5 BPE tokens on Claude;

### `μ` (mu) — friction

- `specs/01_GLYPHS.csl:201` — | μ     | friction / viscosity                    |
- `specs/04_SPATIAL.csl:28` — μ : f32 ⌈0..1⌉
- `specs/06_SPEC.csl:123` — ⌈handle @req < 100μs⌉             # latency budget
- `specs/12_TOKENIZER.csl:171` — | μ       | mu        | friction     |
- `eval/RESULTS.md:119` — - Tier-2 glyphs (ρ μ σ κ ε τ, APL ops) cost 3-5 BPE tokens on Claude;

### `σ` (sigma) — stress

- `specs/01_GLYPHS.csl:202` — | σ     | stress / conductivity                   |
- `specs/04_SPATIAL.csl:29` — σ : [f32;6]
- `specs/04_SPATIAL.csl:30` — ¬σ < 0 @compression     # indent = Peircean cut = negation scope
- `specs/12_TOKENIZER.csl:172` — | σ       | sigma     | stress       |
- `eval/RESULTS.md:119` — - Tier-2 glyphs (ρ μ σ κ ε τ, APL ops) cost 3-5 BPE tokens on Claude;

### `κ` (kappa) — curvature

- `specs/01_GLYPHS.csl:203` — | κ     | curvature / thermal conductivity        |
- `specs/12_TOKENIZER.csl:173` — | κ       | kappa     | curvature    |
- `eval/RESULTS.md:119` — - Tier-2 glyphs (ρ μ σ κ ε τ, APL ops) cost 3-5 BPE tokens on Claude;

### `ε` (eps) — strain

- `specs/01_GLYPHS.csl:204` — | ε     | strain / permittivity                   |
- `specs/12_TOKENIZER.csl:174` — | ε       | eps       | strain       |
- `eval/RESULTS.md:119` — - Tier-2 glyphs (ρ μ σ κ ε τ, APL ops) cost 3-5 BPE tokens on Claude;

### `τ` (tau) — torque

- `specs/01_GLYPHS.csl:206` — | τ     | torque / time constant                  |
- `specs/12_TOKENIZER.csl:175` — | τ       | tau       | torque       |
- `eval/RESULTS.md:119` — - Tier-2 glyphs (ρ μ σ κ ε τ, APL ops) cost 3-5 BPE tokens on Claude;

## Apocky-decision block

- UNUSED           (0): —
- INVENTORY-ONLY   (0): —
- USED             (6): ρ μ σ κ ε τ

No spec edits performed by this audit — per T18 non-goal.
If Apocky approves pruning, remove rows from `specs/12_TOKENIZER.csl`
master table and regenerate `parser/glyph_aliases.json`.
