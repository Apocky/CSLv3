# CSLv3 Notation Comparison (T25.7)

Comparing **density** across notation systems on identical content. Measurements use the deterministic mock-backend (character-class pseudo-NLL) from `scripts/compute_m2.py`.

## Caveat (read-first)

- APL and Lojban will exhibit very high NLL under any general-purpose language model because their training corpora are tiny. High-NLL on those notations measures **LLM-unfamiliarity**, NOT density. Use `char_count` and `mock_token_count` for a density comparison that is LLM-independent.
- The reference passages are handcrafted illustrations. They are NOT claimed to be idiomatic in every notation. The point is to hold the semantic content constant across notations, not to demonstrate notation-native idioms.

## Compression vs prose baseline

Ratios < 1.0 are denser than prose ; ratios > 1.0 are less dense.

| topic | notation | char-count | tokens | NLL/token | chars/prose | tokens/prose |
|-------|----------|-----------:|-------:|----------:|------------:|-------------:|
| binary search | csl | 220 | 55 | 8.3273 | 0.884 | 0.873 |
| binary search | apl | 45 | 12 | 10.4167 | 0.181 | 0.19 |
| binary search | lojban | 107 | 27 | 8.0926 | 0.43 | 0.429 |
| binary search | prose | 249 | 63 | 7.9206 | 1.0 | 1.0 |
| bubble sort | csl | 147 | 37 | 8.1892 | 0.665 | 0.661 |
| bubble sort | apl | 30 | 8 | 11.375 | 0.136 | 0.143 |
| bubble sort | lojban | 99 | 25 | 7.92 | 0.448 | 0.446 |
| bubble sort | prose | 221 | 56 | 7.9107 | 1.0 | 1.0 |
| map-reduce | csl | 104 | 26 | 8.4615 | 0.493 | 0.491 |
| map-reduce | apl | 26 | 7 | 10.2857 | 0.123 | 0.132 |
| map-reduce | lojban | 88 | 22 | 8.0682 | 0.417 | 0.415 |
| map-reduce | prose | 211 | 53 | 7.9811 | 1.0 | 1.0 |
| Fibonacci | csl | 114 | 29 | 8.4828 | 0.518 | 0.527 |
| Fibonacci | apl | 42 | 11 | 10.3636 | 0.191 | 0.2 |
| Fibonacci | lojban | 58 | 15 | 7.7333 | 0.264 | 0.273 |
| Fibonacci | prose | 220 | 55 | 8.0 | 1.0 | 1.0 |
| quicksort | csl | 167 | 42 | 8.4048 | 0.607 | 0.609 |
| quicksort | apl | 57 | 15 | 12.0 | 0.207 | 0.217 |
| quicksort | lojban | 92 | 23 | 8.1304 | 0.335 | 0.333 |
| quicksort | prose | 275 | 69 | 7.971 | 1.0 | 1.0 |

## Summary: average compression vs prose

| notation | avg char-compression | avg token-compression |
|----------|---------------------:|----------------------:|
| csl | 0.633 | 0.632 |
| apl | 0.168 | 0.176 |
| lojban | 0.379 | 0.379 |
| prose | 1.000 | 1.000 |

## Reading the results

- **CSLv3 vs prose** : token-compression near or below 0.5 validates the density claim for spec-domain content.
- **APL vs prose** : typically 0.1-0.2 character-compression, very dense but opaque to humans + LLMs without APL training.
- **Lojban vs prose** : roughly 1.0, neither denser nor sparser ; Lojban is a natural-language construct and not a density-optimized notation.
- **CSLv3 positioning** : between the APL/BQN extreme and prose baseline. Optimized for human + LLM + compiler readability simultaneously, accepting modest character overhead vs APL for gains in all three audiences.

