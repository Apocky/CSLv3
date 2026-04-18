# § M2 FINETUNE INTERPRETATION — Session-16 (LoRA-proper)

generated_at : 2026-04-17
base-model   : `Qwen/Qwen2.5-1.5B-Instruct`
adapters     : 3
  - **joint** : `artifacts/lora_weights/joint/final`
  - **csl-only** : `artifacts/lora_weights/csl-only/final`
  - **en-only** : `artifacts/lora_weights/en-only/final`

## Summary

- pre-tune mean m₂ (base alone) : **1.0958**

| adapter | post mean m₂ | Δ m₂ | CSL mean ΔNLL | EN mean ΔNLL |
|---------|-------------:|-----:|--------------:|-------------:|
| **joint** | 1.1111 | +0.0153 | -0.0688 | -0.0970 |
| **csl-only** | 1.0468 | -0.0490 | -0.1695 | -0.0420 |
| **en-only** | 1.1317 | +0.0359 | -0.0427 | -0.1187 |

## Hypothesis verdicts per adapter

- **joint** : H1 (ΔCSL < ΔEN) = ✗ NOT CONFIRMED ; H2 (m₂ → 1.0) = ✗ NOT CONFIRMED
- **csl-only** : H1 (ΔCSL < ΔEN) = ✓ CONFIRMED ; H2 (m₂ → 1.0) = ✓ CONFIRMED
- **en-only** : H1 (ΔCSL < ΔEN) = ✗ NOT CONFIRMED ; H2 (m₂ → 1.0) = ✗ NOT CONFIRMED

## Per-file delta — adapter `joint`

| file | mode | pre m₂ | post m₂ | Δ m₂ | Δ CSL-NLL | Δ EN-NLL |
|------|------|-------:|--------:|-----:|----------:|---------:|
| C10_changelog_narrative | prose | 0.927 | 0.929 | +0.002 | -0.050 | -0.059 |
| C1_sort | pure-CSL | 1.079 | 1.096 | +0.017 | -0.063 | -0.089 |
| C2_nested_scopes | pure-CSL | 0.875 | 0.890 | +0.015 | -0.041 | -0.096 |
| C3_dependent_types | pure-CSL | 1.467 | 1.489 | +0.022 | -0.080 | -0.088 |
| C4_reason_block | pure-CSL | 1.259 | 1.282 | +0.023 | -0.087 | -0.121 |
| C5_bridge_mode | bridge | 1.206 | 1.233 | +0.027 | -0.106 | -0.152 |
| C6_slot_grammar | pure-CSL | 0.937 | 0.952 | +0.015 | -0.071 | -0.122 |
| C7_morpheme_stack | pure-CSL | 1.290 | 1.314 | +0.023 | -0.057 | -0.082 |
| C8_design_retrospective | prose | 0.946 | 0.947 | +0.001 | -0.055 | -0.061 |
| C9_tutorial_style | prose | 0.971 | 0.979 | +0.007 | -0.079 | -0.099 |

## Per-file delta — adapter `csl-only`

| file | mode | pre m₂ | post m₂ | Δ m₂ | Δ CSL-NLL | Δ EN-NLL |
|------|------|-------:|--------:|-----:|----------:|---------:|
| C10_changelog_narrative | prose | 0.927 | 0.912 | -0.016 | -0.092 | -0.050 |
| C1_sort | pure-CSL | 1.079 | 1.017 | -0.061 | -0.152 | -0.026 |
| C2_nested_scopes | pure-CSL | 0.875 | 0.836 | -0.038 | -0.135 | -0.025 |
| C3_dependent_types | pure-CSL | 1.467 | 1.373 | -0.094 | -0.259 | -0.030 |
| C4_reason_block | pure-CSL | 1.259 | 1.197 | -0.062 | -0.236 | -0.042 |
| C5_bridge_mode | bridge | 1.206 | 1.154 | -0.053 | -0.226 | -0.057 |
| C6_slot_grammar | pure-CSL | 0.937 | 0.892 | -0.045 | -0.161 | -0.035 |
| C7_morpheme_stack | pure-CSL | 1.290 | 1.205 | -0.085 | -0.212 | -0.021 |
| C8_design_retrospective | prose | 0.946 | 0.933 | -0.013 | -0.090 | -0.053 |
| C9_tutorial_style | prose | 0.971 | 0.948 | -0.023 | -0.133 | -0.081 |

## Per-file delta — adapter `en-only`

| file | mode | pre m₂ | post m₂ | Δ m₂ | Δ CSL-NLL | Δ EN-NLL |
|------|------|-------:|--------:|-----:|----------:|---------:|
| C10_changelog_narrative | prose | 0.927 | 0.933 | +0.006 | -0.051 | -0.073 |
| C1_sort | pure-CSL | 1.079 | 1.126 | +0.047 | -0.027 | -0.110 |
| C2_nested_scopes | pure-CSL | 0.875 | 0.897 | +0.023 | -0.031 | -0.110 |
| C3_dependent_types | pure-CSL | 1.467 | 1.529 | +0.062 | -0.020 | -0.107 |
| C4_reason_block | pure-CSL | 1.259 | 1.309 | +0.050 | -0.053 | -0.153 |
| C5_bridge_mode | bridge | 1.206 | 1.267 | +0.060 | -0.049 | -0.183 |
| C6_slot_grammar | pure-CSL | 0.937 | 0.975 | +0.038 | -0.034 | -0.148 |
| C7_morpheme_stack | pure-CSL | 1.290 | 1.343 | +0.053 | -0.021 | -0.102 |
| C8_design_retrospective | prose | 0.946 | 0.951 | +0.005 | -0.053 | -0.072 |
| C9_tutorial_style | prose | 0.971 | 0.987 | +0.016 | -0.088 | -0.128 |

## Isolation signature

If training on **csl-only** lowers CSL-NLL more than EN-NLL, the 
adapter is learning the CSL token-distribution independently. Symmetrically for **en-only**. A **joint** adapter trained on (EN-prompt, CSL-completion) pairs should show mixed behaviour.

```
joint       ΔCSL=-0.0688  ΔEN=-0.0970  => EN-dominant
csl-only    ΔCSL=-0.1695  ΔEN=-0.0420  => CSL-dominant
en-only     ΔCSL=-0.0427  ΔEN=-0.1187  => EN-dominant
```

## Honest-science notes

Session-14 ran at 0.5 B-CPU with joint training and reported NOT-CONFIRMED for H1 and H2. Session-16 scales to a larger base (`Qwen/Qwen2.5-1.5B-Instruct`) and adds the isolation experiment (csl-only vs en-only). The reported deltas are **on the training corpus** — data leakage is intentional because we need the m₂ signal at measurable scale with this corpus size. A generalisation experiment with a held-out fixture set is Session-17+ work.

Key result : if csl-only shows a CSL-dominant signature and en-only shows an EN-dominant signature, this confirms that a LoRA adapter is learning the token-distribution it was trained on — which is unsurprising mechanistically but has not been empirically demonstrated on the CSLv3 corpus before this session.

If the joint adapter produces a balanced signature, it indicates the prompt-masking setup is doing its job (only CSL contributes to the loss) but the adapter still ends up influencing both NLLs — likely because the base model's representation already couples the two distributions.

Per Session-12 handoff : negative results are reportable. Whichever signature emerges, the data above is the data.
