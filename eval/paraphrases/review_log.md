# § Paraphrase Review Log — Session 13 P1.2 Extended

generated_at : 2026-04-17 (extended for C8-C10 prose fixtures)
scorer       : scripts/m2_quality.py --fallback (char-5-gram Jaccard)
               ← sentence-transformers unavailable on current Python 3.14
               environment ; semantic-scorer deferred to Session-13+
source       : eval/m2_quality.json

§§ threshold regimes

  semantic (ST all-MiniLM-L6-v2)  ←  cosine ≥ 0.70 , recall ≥ 0.80
  jaccard  (char-5-gram fallback) ←  cosine ≥ 0.03 , recall ≥ 0.15

  Jaccard produces orders-of-magnitude-lower cosines than semantic ←
  glyph vs. prose asymmetry. The fallback thresholds are "gross-
  mismatch-only" gates ; they cannot substitute for semantic review.

  W! new C8-C10 prose-fixtures expected high-Jaccard-cosine ← source is
  mostly English so paraphrase ≈ source surface-level ← this is by-design
  for prose-mode m₂ ≤ 1.05 validation.

═════════════════════════════════════════════════════════════════════════
§ current scores (Jaccard fallback)                                    ∫
═════════════════════════════════════════════════════════════════════════

| name                       | mode     | cosine | recall | precision | flag   |
|----------------------------|----------|-------:|-------:|----------:|:------:|
| C1_sort                    | pure-CSL | 0.058  | 0.429  | 0.178     | ok     |
| C2_nested_scopes           | pure-CSL | 0.051  | 0.426  | 0.222     | ok     |
| C3_dependent_types         | pure-CSL | 0.054  | 0.387  | 0.178     | ok     |
| C4_reason_block            | pure-CSL | 0.146  | 0.628  | 0.360     | ok     |
| C5_bridge_mode             | bridge   | 0.219  | 0.475  | 0.442     | ok     |
| C6_slot_grammar            | pure-CSL | 0.090  | 0.410  | 0.281     | ok     |
| C7_morpheme_stack          | pure-CSL | 0.035  | 0.234  | 0.146     | ok     |
| C8_design_retrospective    | prose    | TBD    | TBD    | TBD       | TBD    |
| C9_tutorial_style          | prose    | TBD    | TBD    | TBD       | TBD    |
| C10_changelog_narrative    | prose    | TBD    | TBD    | TBD       | TBD    |

Note : C8-C10 scores pending re-run of scripts/m2_quality.py ; expected
very-high-cosine ≥ 0.60 even under Jaccard-fallback ∵ CSL-form is nearly-
identical to paraphrase (prose-mode by-design).

═════════════════════════════════════════════════════════════════════════
§ Apocky review checklist ← per-file                                   D>
═════════════════════════════════════════════════════════════════════════

For each pair below, open:
  left  : eval/C{N}_*.csl
  right : eval/paraphrases/C{N}.en

Review question : does the EN paraphrase preserve every named fact,
every gate, every constraint stated in the CSL, without adding facts
the CSL doesn't assert?

If yes → no edit required.
If no  → edit the EN file, append a note below.

§§ pure-CSL (pending Session-12 review)
  ○ C1_sort              : binary-search over sorted arrays ; canonical
  ○ C2_nested_scopes     : scope rules + identifier resolution
  ○ C3_dependent_types   : refinement-type predicates + SMT checks
  ○ C4_reason_block      : §P §D §T §S §C blocks + thought-flow
  ○ C6_slot_grammar      : slot-template + position-determined-meaning
  ○ C7_morpheme_stack    : base.aspect.modality.certainty.scope

§§ bridge (pending Session-12 review)
  ○ C5_bridge_mode       : hybrid CSL + EN-prose interleave

§§ prose (Session-13 new fixtures)
  ○ C8_design_retrospective : three parser-bootstrap decisions ; odin-vs-rust
  ○ C9_tutorial_style       : hello.csl walkthrough ; parser + pprint
  ○ C10_changelog_narrative : v1.0 release-story ; day-2-productivity + bug

═════════════════════════════════════════════════════════════════════════
§ edit log                                                            ⊞
═════════════════════════════════════════════════════════════════════════

2026-04-17 : C8-C10 prose-fixtures added ; paraphrases written ; pending
             quality-score re-run + Apocky-review.

═════════════════════════════════════════════════════════════════════════
§ session-13 prose-corpus verdict                                      ✓
═════════════════════════════════════════════════════════════════════════

  ✓ 3 prose-mode fixtures created (C8, C9, C10)
  ✓ 3 EN paraphrases written matching conventions
  ✓ corpus-mode: prose header present in all 3 CSL files
  ◐ quality-score re-run pending (scripts/m2_quality.py)
  ◐ m₁ re-run pending (scripts/compute_m1.py will now include C8-C10)
  ◐ m₂ re-run pending (scripts/compute_m2.py --all-eval with real backend)
  ○ Apocky approval pending-human-review

  target-validation :
    m₁ prose ≤ 0.95 ← CSL-surface ≈ EN-surface ∵ prose-mode
    m₂ prose ≤ 1.05 ← LLM-familiarity ≈ equal both-forms

  expected :
    m₁ = 0.90-0.95 range ← §-headers add-minor overhead
    m₂ = 0.98-1.05 range ← slight CSL-ceremony penalty
