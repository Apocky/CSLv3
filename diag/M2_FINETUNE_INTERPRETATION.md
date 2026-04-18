# § M2 FINETUNE INTERPRETATION — Session-14

generated_at : 2026-04-17
base-model   : `Qwen/Qwen2.5-0.5B-Instruct`
adapter      : `artifacts/lora_weights/final`
training     : 3 epochs, rank=8, lr=2e-4, corpus=10 pairs

## Summary

- pre-tune mean m₂  : **1.0562**
- post-tune mean m₂ : **1.0595**
- mean Δm₂          : **+0.0033**
- CSL mean ΔNLL     : -0.0680  (10/10 files improved)
- EN  mean ΔNLL     : -0.0740  (10/10 files improved)

## Hypothesis verdicts

- H1 (CSL-NLL drops faster than EN-NLL under adapter) : ✗ NOT CONFIRMED — adapter helped EN equal-or-more than CSL
- H2 (post-tune m₂ moves toward 1.0) : ✗ NOT CONFIRMED

## Per-file delta table

| file | mode | pre m₂ | post m₂ | Δ m₂ | Δ CSL-NLL | Δ EN-NLL |
|------|------|-------:|--------:|-----:|----------:|---------:|
| C10_changelog_narrative | prose | 0.930 | 0.930 | -0.000 | -0.047 | -0.050 |
| C1_sort | pure-CSL | 1.036 | 1.030 | -0.007 | -0.075 | -0.058 |
| C2_nested_scopes | pure-CSL | 0.864 | 0.872 | +0.008 | -0.042 | -0.080 |
| C3_dependent_types | pure-CSL | 1.365 | 1.368 | +0.003 | -0.088 | -0.070 |
| C4_reason_block | pure-CSL | 1.250 | 1.266 | +0.015 | -0.058 | -0.086 |
| C5_bridge_mode | bridge | 1.123 | 1.133 | +0.011 | -0.092 | -0.113 |
| C6_slot_grammar | pure-CSL | 0.906 | 0.906 | +0.000 | -0.069 | -0.077 |
| C7_morpheme_stack | pure-CSL | 1.170 | 1.170 | +0.000 | -0.093 | -0.080 |
| C8_design_retrospective | prose | 0.954 | 0.953 | -0.001 | -0.052 | -0.049 |
| C9_tutorial_style | prose | 0.964 | 0.968 | +0.004 | -0.063 | -0.077 |

## By corpus-mode

- **bridge** (1 files) : pre 1.123 → post 1.133  Δ +0.011
- **prose** (3 files) : pre 0.949 → post 0.950  Δ +0.001
- **pure-CSL** (6 files) : pre 1.099 → post 1.102  Δ +0.003

## Honest-science interpretation

A LoRA adapter with rank 8, trained for 3 epochs on 10 EN→CSL pairs over a 0.5 B-parameter base model, is a very small intervention. The above deltas should be read as **smoke-test** evidence that the fine-tune pipeline works end-to-end, not as a publishable claim that fine-tuning reliably moves m₂ toward 1.0 on this corpus.

Meaningful follow-up experiments (Session-15+) : (a) larger base (1.5B–7B) with CUDA training ; (b) larger corpus (expand beyond 10 pairs) ; (c) rank sweep {4, 16, 32, 64} ; (d) paired fine-tune on CSL-only vs EN-only to isolate which token-distribution the adapter is actually learning ; (e) post-tune comparison against GGUF re-quant (round-trips through the existing cli-daemon harness so numbers are directly comparable to the v1.2.0 baseline).

Per the Session-12 handoff's pre-authorization of negative-result reporting : the numbers above are reported as-measured. If H1 or H2 did not confirm, this is a data point, not a failure of the thesis — the m₂-to-density chain has independent variables (base-model capacity, fine-tune scale, corpus size) that a small-scale experiment cannot isolate.
