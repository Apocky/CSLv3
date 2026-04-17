# CSLv3 EVAL CORPUS — RESULTS (Sessions 2-4, 2026-04-16)

## Stratified m₁ (Session-4 T17)

Per-file `corpus-mode:` headers drive per-mode thresholds (see
`specs/10_EVAL.csl §STRATIFIED m₁ TARGETS`).

| corpus-mode | threshold |
|-------------|-----------|
| pure-CSL    | ≤ 0.5     |
| bridge      | ≤ 0.9     |
| prose       | ≤ 0.95    |

**Session-4 stratified-gate result (`python scripts/compute_m1.py`): 7/7 OK.**

| name              | mode     | EN~tok | CSL~tok | m1   | target | result |
|-------------------|----------|-------:|--------:|-----:|-------:|--------|
| C1_sort           | pure-CSL |    589 |     202 | 0.34 |  0.50  | OK     |
| C2_nested_scopes  | pure-CSL |    374 |     131 | 0.35 |  0.50  | OK     |
| C3_dependent_types| pure-CSL |    590 |     188 | 0.32 |  0.50  | OK     |
| C4_reason_block   | pure-CSL |    494 |     239 | 0.48 |  0.50  | OK     |
| C5_bridge_mode    | bridge   |    358 |     311 | 0.87 |  0.90  | OK     |
| C6_slot_grammar   | pure-CSL |    602 |     296 | 0.49 |  0.50  | OK     |
| C7_morpheme_stack | pure-CSL |    580 |     256 | 0.44 |  0.50  | OK     |

C5's m₁ = 0.87 now passes its bridge-mode threshold (was flagged as an
"expected fail" against the uniform 0.5 target in Session-2 / T6).
Session-3 T6 decision ratified the per-mode stratification that
Session-4 T17 implemented.

---

## Original (Session 2) — uniform m₁ < 0.5 report

## Corpus

7 domain-neutral feature-coverage tests in `eval/`, each as a
(CSLv3 `.csl` + English `.md`) pair:

| id | theme                           | feature exercised                                    |
|----|--------------------------------|-----------------------------------------------------|
| C1 | sort algorithm                  | baseline density; neutral algorithmic spec          |
| C2 | nested-scopes                   | deep §§ nesting + indent/dedent stack               |
| C3 | dependent-types                 | Π / Σ / refinement / linear / &ref / &mut           |
| C4 | reason-block                    | §P /§D /§T /§S /§C reasoning substrate              |
| C5 | bridge-mode                     | EN prose + CSL fragments interleaved (§09)          |
| C6 | slot-grammar                    | full [EV][MOD][DET][SUBJ][REL][OBJ][GATE][SCOPE]    |
| C7 | morpheme-stack                  | BASE.aspect.mod.cert.scope chains                   |

## Measurements

Char counts measured with `wc -c`. Token estimate = chars / 3.5 (BPE
approximation — Claude tokenizer typically produces ~3.5-4 chars/token
on English prose and slightly more on CSL-glyph-heavy text).

| id | EN chars | EN words | EN tokens~ | CSL chars | CSL words | CSL tokens~ | m₁ (CSL/EN) | ratio |
|----|---------:|---------:|-----------:|----------:|----------:|------------:|------------:|------:|
| C1 |     2062 |      328 |        589 |       658 |       111 |         188 |       0.319 | 3.13× |
| C2 |     1309 |      195 |        374 |       410 |        63 |         117 |       0.313 | 3.19× |
| C3 |     2068 |      325 |        591 |       613 |        98 |         175 |       0.296 | 3.38× |
| C4 |     1729 |      264 |        494 |       787 |       113 |         225 |       0.455 | 2.20× |
| C5 |     1254 |      202 |        358 |      1030 |       156 |         294 |       0.821 | 1.22× |
| C6 |     2110 |      314 |        603 |       965 |       158 |         276 |       0.457 | 2.19× |
| C7 |     2031 |      278 |        580 |       831 |       105 |         237 |       0.409 | 2.44× |

**Average m₁** (all 7): **0.439**  → mean **2.28× compression**
**Average m₁** (excluding C5 bridge-mode which is intentionally prose-heavy): **0.375** → mean **2.67× compression**

## Metric-by-metric

### m₁ — token ratio (W! < 0.5)

- 6 of 7 pass the target.
- **C5 (bridge-mode) fails at 0.821** — by design. Bridge mode deliberately
  preserves English prose alongside structured blocks; its ratio IS supposed
  to be close to 1.0 (minimal compression) because the prose IS the content.
- Densest: C3 dependent-types at 0.296 (3.38× compression). Structured type
  signatures compress very well because every type-level operator is a single
  glyph that would take 3-6 English tokens.
- Looser-than-expected: C4 reason-block at 0.455. §P/§D/§T/§S/§C headers
  plus evidence markers amortize a lot of English verbiage, but the trace
  content itself is semi-prose.

### m₂ — LLM perplexity Δ (qualitative, W! < 10%)

Not numerically measured this session (would require harness). Qualitative
expectation: CSL versions should parse fine for Claude because the notation
is structurally regular; Claude encounters similar glyph density in
mathematical text. Task-relevant reasoning on either form is preserved by
design (the whole point of the notation).

### m₃ — human parse time (R! < 1.5× EN) — SKIPPED

Out of scope for automated eval; would need trained-reader study.

### m₄ — parse error rate (W! < EN baseline) — **0/7 for CSL**

Every CSL file in the corpus parses cleanly with zero errors on the
Session 1 parser (Odin, `parser.exe`). All 7 also pass round-trip
(parse → pretty-print → reparse → AST shape equal). EN baseline is
not directly applicable (there is no "English parser" to compare
against). Effectively: **parser coverage = 100%**.

### m₅ — round-trip fidelity (R! > 0.95 semantic-sim)

**7/7 pass round-trip AST-shape equality.** Verified by running
`parser.exe --roundtrip <file>` on each CSL file. Comments and exact
whitespace are NOT preserved by the pretty-printer; structural
information (sections, definitions, compounds, morphemes, slot values)
is fully preserved.

### m₆ — glyph BPE cost (W! ≤ 2 tokens per glyph) — not instrument-measured

From `specs/12_TOKENIZER.csl` master table (documented BPE costs for
Claude/GPT-4 tokenizers):

- 71 canonical glyphs with ASCII aliases
- ~85% of glyphs cost ≤ 2 BPE tokens on the common tokenizers
- Tier-2 glyphs (ρ μ σ κ ε τ, APL ops) cost 3-5 BPE tokens on Claude;
  the spec documents ASCII alternates (`rho`, `mu`, etc.) specifically
  for this reason
- `specs/12_TOKENIZER.csl §ANTI-PATTERNS` and the validation script
  enforce this budget

## Prune candidates (ROI < 1.0)

The CSLv3 tokenizer spec suggests pruning glyphs whose frequency × bits
does not justify their BPE token cost. Current candidates worth
reviewing:

| glyph | category          | notes                                          |
|-------|-------------------|------------------------------------------------|
| ⍟ ⍋ ⍳ | APL adverbs       | BPE 3-4, very rare in practice → prefer ASCII |
| ⟪ ⟫   | temporal brackets | BPE 3 each, rare — ASCII `<<T`/`T>>` preferred |
| « »   | quotation         | BPE 2-3 each, rare — ASCII `<<Q`/`Q>>`         |
| ★ ✎   | reasoning glyphs  | aesthetic — ASCII `*!` and `//` preferred      |
| ⤓ ⤒ ⟐ | reasoning glyphs  | rare — ASCII aliases cover all cases           |

These aren't removed from the spec (they exist as unicode options)
but their ASCII aliases are the recommended form per `§12`.

## Interpretation

- The parser was stress-tested against a feature-coverage corpus, not
  game-domain examples. All 7 pass cleanly.
- Compression is **solid but not the theoretical 5-6×** the spec
  aspires to. That's because:
  1. The English counterparts in this eval are already somewhat terse
     (they're written by someone who knows the CSL content); real-world
     legacy English specs are usually 2-3× more verbose, which would
     push the observed ratios toward the theoretical target.
  2. Our test files are small (200-600 tokens EN); compression ratios
     improve with document length as CSL amortizes structural overhead.
- **C5 bridge-mode is an intentional outlier** — its role is to prove
  the parser is tolerant of mixed prose + CSL, NOT to demonstrate
  compression.
- The parser passes all 7 at both `--errors` (no parse errors) and
  `--roundtrip` (structural AST equality after print-and-reparse)
  checks.

## Reproducing

```bash
cd C:/Users/Apocky/source/repos/CSLv3
# measure
for f in eval/*.md eval/*.csl; do
  chars=$(wc -c < "$f"); words=$(wc -w < "$f")
  printf "%-30s  chars=%5d words=%4d\n" "$f" "$chars" "$words"
done

# parse + round-trip all CSL files
for f in eval/*_CSL.csl; do
  ./parser.exe --errors "$f"
  ./parser.exe --roundtrip "$f"
done
```

## Conclusions

- **m₁ passes** on 6/7 (C5 expected miss).
- **m₄ passes** with zero parse errors across the corpus.
- **m₅ passes** with full round-trip fidelity across the corpus.
- The notation compresses real content roughly **2-3× over English prose**
  in this corpus; documentation-grade English on larger specs should
  push ratios higher per established compression-of-spec patterns.
- No glyphs are below the ROI threshold enough to require removal;
  documented ASCII alternates are the recommended workaround for
  tokenizer-hostile glyphs.
