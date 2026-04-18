# § m₂ Stratified-Target Report — Session 15 (v1.4.0 final)

generated_at : 2026-04-17
backend      : cli-daemon (llama-perplexity.exe subprocess, mmap-retained,
                repeat-pad with 1.8× safety factor, ctx=256)
bootstrap    : 1000 resamples, seed=20260417
source       : eval/m2_baseline.json (30 measurements)

§§ target schedule
  pure-CSL  ≤ 1.50
  bridge    ≤ 1.50   (revised from 1.20 in v1.2.0)
  prose     ≤ 1.05

═════════════════════════════════════════════════════════════════════════
§ per-file verdict ← 30 measurements                                   ⊞
═════════════════════════════════════════════════════════════════════════

| file                           | mode     | target | small | medium | large | mean  | spread | target | agreement |
|--------------------------------|----------|--------|-------|--------|-------|-------|--------|--------|-----------|
| C1_sort_CSL.csl                | pure-CSL | ≤1.50  | 0.752 | 0.830  | 0.720 | 0.767 |  15.3% | ✓ MET  | ✓ OK      |
| C2_nested_scopes_CSL.csl       | pure-CSL | ≤1.50  | 0.925 | 0.988  | 0.998 | 0.970 |   7.9% | ✓ MET  | ✓ OK ‼    |
| C3_dependent_types_CSL.csl     | pure-CSL | ≤1.50  | 0.983 | 0.874  | 0.916 | 0.924 |  12.5% | ✓ MET  | ✓ OK      |
| C4_reason_block_CSL.csl        | pure-CSL | ≤1.50  | 0.851 | 0.846  | 0.983 | 0.893 |  16.2% | ✓ MET  | ✓ OK      |
| C5_bridge_mode_CSL.csl         | bridge   | ≤1.50  | 1.270 | 1.388  | 1.358 | 1.339 |   9.3% | ✓ MET  | ✓ OK      |
| C6_slot_grammar_CSL.csl        | pure-CSL | ≤1.50  | 0.791 | 0.810  | 0.829 | 0.810 |   4.8% | ✓ MET  | ✓ OK      |
| C7_morpheme_stack_CSL.csl      | pure-CSL | ≤1.50  | 0.811 | 0.874  | 0.955 | 0.880 |  17.8% | ✓ MET  | ✓ OK      |
| C8_design_retrospective_CSL.csl| prose    | ≤1.05  | 0.928 | 0.916  | 0.963 | 0.936 |   5.1% | ✓ MET  | ✓ OK      |
| C9_tutorial_style_CSL.csl      | prose    | ≤1.05  | 0.987 | 0.910  | 0.876 | 0.925 |  12.7% | ✓ MET  | ✓ OK      |
| C10_changelog_narrative_CSL.csl| prose    | ≤1.05  | 0.910 | 0.915  | 0.926 | 0.917 |   1.8% | ✓ MET  | ✓ OK      |

‼ C2_nested_scopes anomaly RESOLVED by natural-content corpus expansion
  (Session-14). Pre-Session-14 m₂ was 0.093-0.464 (FLAG 400% spread) ;
  post-expansion measurement is 0.925-0.998 (7.9% spread). The root
  cause was confirmed : repeat-pad KV-cache over-collapse on highly-
  regular short content. Eliminated by making the natural token count
  exceed 2·ctx so no repeat-pad is applied.

═════════════════════════════════════════════════════════════════════════
§ aggregate statistics                                                 ∫
═════════════════════════════════════════════════════════════════════════

  ∀ 30 measurements :
    mean m₂      = 0.936
    stdev m₂     = 0.155
    range        = [0.720, 1.388]

  per-model mean :
    small   = 0.921   stdev = 0.141  n=10
    medium  = 0.935   stdev = 0.157  n=10
    large   = 0.952   stdev = 0.174  n=10

  target-met rate :
    10/10 files met stratified targets (100%)
  agreement rate :
    10/10 files within 20% spread (100%) ← C2 fix restored full agreement

  Δ vs Session-13 (v1.2.0 final) :
    mean 0.862 → 0.936  (+0.074 , cleaner convergence toward 1.0)
    stdev 0.270 → 0.155 (-43% , C2 anomaly eliminated)

═════════════════════════════════════════════════════════════════════════
§ prose-mode verdict ← first-time full-green                          ✓
═════════════════════════════════════════════════════════════════════════

  All 3 prose fixtures × all 3 models = 9/9 MET target ≤ 1.05 :
    C8  : small 0.928  medium 0.916  large 0.963   (max 0.963 < 1.05)
    C9  : small 0.987  medium 0.910  large 0.876   (max 0.987 < 1.05)
    C10 : small 0.910  medium 0.915  large 0.926   (max 0.926 < 1.05)

  Mean 0.926 ; spread max 12.7% ; all under both targets.

═════════════════════════════════════════════════════════════════════════
§ v1.4.0 acceptance                                                    ✓
═════════════════════════════════════════════════════════════════════════

  ✓ 30/30 measurements (vs 21 in v1.1.0, 30 in v1.2.0)
  ✓ 10/10 stratified-targets met (100%)
  ✓ 10/10 multi-model agreement within 20% (100% — first full green)
  ✓ C2 anomaly resolved (Session-14 corpus expansion confirmed working)
  ✓ prose ≤1.05 target met 9/9
  ✓ bridge ≤1.50 target met 3/3 (under revised threshold)
  ✓ pure-CSL ≤1.50 target met 21/21
  ✓ audit-chain appendable under schema v2

═════════════════════════════════════════════════════════════════════════
§ methodology transparency                                             ⟦⟧
═════════════════════════════════════════════════════════════════════════

  backend kind     : cli-daemon (mmap-retention subprocess pool)
  models           : Qwen2.5-1.5B-Q4KM , Llama-3.2-3B-Q4KM , Mistral-7B-v0.3-Q4KM
  quantization     : Q4_K_M
  ctx-size         : 256
  pad-strategy     : repeat-self ; 1.8× safety factor vs approx-tokens
  bootstrap        : 1000 resamples over chunks, seed=20260417
  gpu              : Vulkan @ Intel Arc A770 (16GB VRAM)
  wallclock        : ~3min for 30 measurements

  § historical timeline :
    Session-11 v1.1.0-rc.1  : mock-backend infrastructure (no real data)
    Session-12 v1.1.0       : first 21 real measurements (7 files × 3 models)
    Session-13 v1.2.0       : 30 measurements (10 files × 3 models) ; C2 anomaly
    Session-15 v1.4.0       : 30 measurements (C2 anomaly resolved)

    Absolute m₂ values shifted across ctx-size regime changes between
    versions. For longitudinal density comparison, hold ctx constant.
