# § M2 FINETUNE INTERPRETATION — Session-16 (LoRA-proper)

generated_at : 2026-04-18
base-model   : `Qwen/Qwen2.5-1.5B-Instruct`
adapters     : 1
  - **csl-only-expanded** : `artifacts/lora_weights/csl-only_C1C2C3C4C5C6C7C11C12C13C14C15C16C17C18/final`

## Summary

- pre-tune mean m₂ (base alone) : **1.0292**

| adapter | post mean m₂ | Δ m₂ | CSL mean ΔNLL | EN mean ΔNLL |
|---------|-------------:|-----:|--------------:|-------------:|
| **csl-only-expanded** | 0.9613 | -0.0679 | -0.2067 | -0.0361 |

## Hypothesis verdicts per adapter

- **csl-only-expanded** : H1 (ΔCSL < ΔEN) = ✓ CONFIRMED ; H2 (m₂ → 1.0) = ✗ NOT CONFIRMED

## Per-file delta — adapter `csl-only-expanded`

| file | mode | pre m₂ | post m₂ | Δ m₂ | Δ CSL-NLL | Δ EN-NLL |
|------|------|-------:|--------:|-----:|----------:|---------:|
| C10_changelog_narrative | prose | 0.927 | 0.920 | -0.007 | -0.027 | -0.008 |
| C1_sort | pure-CSL | 1.079 | 1.015 | -0.064 | -0.163 | -0.032 |
| C2_nested_scopes | pure-CSL | 0.875 | 0.829 | -0.045 | -0.163 | -0.035 |
| C3_dependent_types | pure-CSL | 1.467 | 1.378 | -0.089 | -0.265 | -0.042 |
| C4_reason_block | pure-CSL | 1.259 | 1.203 | -0.056 | -0.208 | -0.034 |
| C5_bridge_mode | bridge | 1.206 | 1.161 | -0.045 | -0.200 | -0.055 |
| C6_slot_grammar | pure-CSL | 0.937 | 0.894 | -0.043 | -0.161 | -0.041 |
| C7_morpheme_stack | pure-CSL | 1.290 | 1.205 | -0.085 | -0.219 | -0.026 |
| C8_design_retrospective | prose | 0.946 | 0.938 | -0.008 | -0.041 | -0.015 |
| C9_tutorial_style | prose | 0.971 | 0.962 | -0.010 | -0.039 | -0.016 |
| C11_hashtable | pure-CSL | 0.831 | 0.732 | -0.098 | -0.252 | -0.031 |
| C12_quicksort | pure-CSL | 0.824 | 0.750 | -0.074 | -0.204 | -0.029 |
| C13_ringbuffer | pure-CSL | 0.959 | 0.862 | -0.096 | -0.264 | -0.033 |
| C14_state_machine | pure-CSL | 0.993 | 0.860 | -0.134 | -0.372 | -0.064 |
| C15_event_loop | pure-CSL | 1.031 | 0.938 | -0.092 | -0.309 | -0.050 |
| C16_arena | pure-CSL | 0.976 | 0.893 | -0.083 | -0.290 | -0.050 |
| C17_lru_cache | pure-CSL | 0.990 | 0.878 | -0.112 | -0.262 | -0.031 |
| C18_rate_limiter | pure-CSL | 0.966 | 0.885 | -0.081 | -0.282 | -0.058 |

## Isolation signature

If training on **csl-only** lowers CSL-NLL more than EN-NLL, the 
adapter is learning the CSL token-distribution independently. Symmetrically for **en-only**. A **joint** adapter trained on (EN-prompt, CSL-completion) pairs should show mixed behaviour.

```
csl-only-expanded  ΔCSL=-0.2067  ΔEN=-0.0361  => CSL-dominant
```

## Honest-science notes

Session-14 ran at 0.5 B-CPU with joint training and reported NOT-CONFIRMED for H1 and H2. Session-16 scales to a larger base (`Qwen/Qwen2.5-1.5B-Instruct`) and adds the isolation experiment (csl-only vs en-only). The reported deltas are **on the training corpus** — data leakage is intentional because we need the m₂ signal at measurable scale with this corpus size. A generalisation experiment with a held-out fixture set is Session-17+ work.

Key result : if csl-only shows a CSL-dominant signature and en-only shows an EN-dominant signature, this confirms that a LoRA adapter is learning the token-distribution it was trained on — which is unsurprising mechanistically but has not been empirically demonstrated on the CSLv3 corpus before this session.

If the joint adapter produces a balanced signature, it indicates the prompt-masking setup is doing its job (only CSL contributes to the loss) but the adapter still ends up influencing both NLLs — likely because the base model's representation already couples the two distributions.

Per Session-12 handoff : negative results are reportable. Whichever signature emerges, the data above is the data.
