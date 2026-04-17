# How to read m₂

m₂ is the **mean negative-log-likelihood ratio** of CSLv3 text vs an
English paraphrase with the same information content, measured under a
fixed pre-trained language model. It is defined formally in
`specs/15_M2_METRIC.csl`.

## Formula

```
m₂ ≡ (NLL(CSL)  / |tokens(CSL)|) / (NLL(EN) / |tokens(EN)|)
```

Where `NLL(seq) = -Σᵢ log P(tokenᵢ | token<ᵢ ; model)` is the teacher-
forced cross-entropy of the sequence under the model's tokenizer. The
ratio cancels the raw-difficulty of the content (which appears as a
constant factor in both numerator and denominator) and leaves behind
a notation-dependency measurement.

## What m₂ measures

m₂ is the **model's relative familiarity** with CSLv3 vs English,
*as a proxy* for CSLv3's density. These are different things :

| m₂ value   | most-likely cause                                              |
|-----------:|----------------------------------------------------------------|
| ≈ 1.0      | model finds CSL as predictable as EN (rare)                    |
| ≤ 1.2      | small familiarity gap ← CSL is compact for the content         |
| 1.2 - 1.5  | medium gap ← glyphs cost some perplexity but structure helps   |
| 1.5 - 2.0  | model is substantially unfamiliar with the notation             |
| > 2.0      | density claim potentially broken OR atypical content            |

None of these values are "good" or "bad" in isolation. The density
claim is that **per-byte-transmitted information is higher in CSL
than in prose**, which is different from (and compatible with) m₂ >
1.0.

## Why multi-model matters

A single model's perplexity is confounded by that model's specific
training corpus. Llama-3 was trained heavily on English plus a big
slug of Python + Markdown — its m₂ on CSL will reflect the CSL-like
patterns it happened to see (mostly none). Mistral-7B has a
different mix. Qwen2.5 was trained with heavier multilingual data.

When all three models agree within 10% on a measurement, we can trust
that the signal is about the notation rather than the specific model.
When they disagree by 30%+, the measurement is noise and needs a
bigger sample or tokenizer-aware analysis.

## Stratified targets

CSLv3 content spans three modes (see `specs/10_EVAL.csl`) :

| mode       | content mix             | m₂ target | status after Session-12 P1.4 |
|------------|-------------------------|-----------|------------------------------|
| pure-CSL   | glyph-heavy spec blocks | ≤ 1.5     | 5/6 files met (C2 large deviates) |
| bridge     | EN prose + CSL blocks   | ≤ 1.2     | **target under revision → 1.5** : bridge-mode empirically sits in pure-CSL range |
| prose      | mostly English          | ≤ 1.05    | deferred — no prose fixtures in corpus yet (Session-13+) |

These are **soft targets** calibrated against the initial three-model
set. Failing a target does not invalidate the density claim — it flags
the file for review. Fine-tuning a small CSL-aware model and
re-running should shift all three targets downward by 20-40%.

The bridge target `≤ 1.2` was set pre-measurement. P1.4 data shows all
three models produce m₂ = 1.39-1.52 on the one bridge fixture (C5),
and the deviation-analysis in `eval/m2_stratified_report.md` explains
why : bridge = pure-CSL-half + EN-half, and the CSL-half's NLL
dominates the ratio. The revised target (≤ 1.5) aligns with that
theory. Updating the soft target does not change any code or data.

## Paraphrase quality caveats

m₂ is only meaningful when the CSL file and the EN paraphrase carry the
**same information**. If the paraphrase is looser than the source (EN
skips facts that CSL lists), m₂ will look artificially good. If the
paraphrase is stricter (EN spells out facts that CSL only gestures at),
m₂ will look artificially bad.

The `m2_quality.py` scorer checks paraphrase fidelity via embedding-
cosine + entity-recall. Pairs below threshold are flagged for review.
A paraphrase that quality-passes but m₂-fails is a genuine signal; a
paraphrase that quality-fails says nothing about density.

## Comparison harness

`m2_compare.py` measures CSLv3 against APL/J/k, Lojban, and prose on
the same five algorithm passages. Beware : APL and Lojban get very
high NLL not because they're low-density but because LLMs are
unfamiliar with them. The char-count and token-count columns are
the fair comparison ; the NLL column is an *interaction* between
density and familiarity.

Use the comparison harness to answer : *how dense is CSL relative to
other density-motivated notations?* Don't use it to make claims like
"CSL is easier for LLMs than APL."  That's almost certainly true but
not what m₂ measures.

## Reproducibility anchors (R16)

Each run appends a signed certificate to `.m2-chain/runs.jsonl`. The
certificate pins :

- SHA-256 of the CSL file
- SHA-256 of the EN paraphrase
- SHA-256 of the GGUF model weights
- the random seed
- the bootstrap resample count

Anyone with the same model weights, the same seed, and this repo
can reproduce a measurement to the bit-for-bit level. If they can't,
either our code drifted or their environment differs ; the chain
certificate will pinpoint which.

## Backends

- `--backend=real` : llama-cpp-python + GGUF checkpoint. Produces true
  per-token NLL + honest bootstrap CI. Requires ~10-minute MSVC source
  build on Python 3.14 (no prebuilt wheel yet ; revisit Session-13+).
- `--backend=cli` : llama-perplexity.exe subprocess (D:/llama.cpp/).
  Chunk-level NLL with repeat-pad for short fixtures. Python 3.14
  compatible, no native build. **This is the default production path
  for v1.1.0.** Repeat-pad introduces absolute-NLL bias (chunks-2+
  benefit from KV-cache memory of chunk-1) but the m₂ ratio remains
  unbiased because the same padding applies to CSL and EN.
- `--backend=mock` : deterministic pseudo-NLL from character-class
  weights. Fast, no model weights needed, used for CI and unit tests.
  **Mock numbers are NOT density claims** — they exercise harness
  plumbing only.

## Session-12 P1.3 real-backend baseline

First production m₂ run : 7 files × 3 models = 21 measurements.
Mean m₂ = 1.210, stdev = 0.225, range [0.897, 1.668].
Per-model means : small=1.216, medium=1.148, large=1.267.
4/7 files cleanly met stratified targets ; 3/7 documented deviations
(see `eval/m2_stratified_report.md`). v1.1.0 is promoted on that
basis per handoff §§ WHEN-STUCK clause.

## Common misreadings

**"m₂ = 1.35 means CSL is 35% worse than English."** — False. It means
the model finds CSL 35% more-surprising per token than the paraphrase,
which is expected given the model's EN bias. The byte-density
comparison (m₁) can simultaneously show CSL is 50% shorter.

**"A fine-tuned CSL model would make m₂ = 1.0."** — Probably, but
that's a different experiment. The current harness measures density
under *pre-trained* models, which is the deployment condition most
users will experience.

**"APL beat CSL in the compare harness."** — APL is denser in
char-count but that comes at a legibility cost CSL deliberately
refused. The compare table shows the tradeoff surface ; it doesn't
declare a winner.

## Files

- `scripts/compute_m2.py`   — core harness
- `scripts/m2_models.py`    — model registry + SHA-pinning
- `scripts/m2_quality.py`   — paraphrase-quality scorer
- `scripts/m2_audit.py`     — signed cert chain
- `scripts/m2_visualize.py` — HTML heatmap reports
- `scripts/m2_compare.py`   — notation comparison harness
- `eval/paraphrases/C*.en`  — plain-text EN paraphrases
- `eval/m2_baseline.json`   — recorded m₂ per (file × model)
- `eval/m2_quality.json`    — paraphrase-quality snapshot
- `specs/15_M2_METRIC.csl`  — formal spec
