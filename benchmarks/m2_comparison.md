# CSLv3 Notation Comparison (T25.7)

Comparing **density** across notation systems on identical content.
Backend : `cli` ; models : large, medium, small

## Caveat (read-first)

- APL and Lojban will exhibit very high NLL under any general-purpose language model because their training corpora are tiny. High-NLL on those notations measures **LLM-unfamiliarity**, NOT density. Use `char_count` and `mock_token_count` for a density comparison that is LLM-independent.
- The reference passages are handcrafted illustrations. They are NOT claimed to be idiomatic in every notation. The point is to hold the semantic content constant across notations, not to demonstrate notation-native idioms.

## Compression vs prose baseline

Ratios < 1.0 are denser than prose ; ratios > 1.0 are less dense.

| topic | notation | model | char-count | tokens | NLL/token | chars/prose | tokens/prose |
|-------|----------|-------|-----------:|-------:|----------:|------------:|-------------:|
| binary search | csl | small | 220 | 4 | 1.0188 | 0.884 | 4.0 |
| binary search | apl | small | 45 | 4 | 0.764 | 0.181 | 4.0 |
| binary search | lojban | small | 107 | 3 | 2.4411 | 0.43 | 3.0 |
| binary search | prose | small | 249 | 0 | 0.0 | 1.0 | 0.0 |
| bubble sort | csl | small | 147 | 3 | 1.1211 | 0.665 | 3.0 |
| bubble sort | apl | small | 30 | 3 | 0.1178 | 0.136 | 3.0 |
| bubble sort | lojban | small | 99 | 3 | 1.5892 | 0.448 | 3.0 |
| bubble sort | prose | small | 221 | 0 | 0.0 | 1.0 | 0.0 |
| map-reduce | csl | small | 104 | 3 | 0.8346 | 0.493 | 1.5 |
| map-reduce | apl | small | 26 | 3 | 0.1132 | 0.123 | 1.5 |
| map-reduce | lojban | small | 88 | 3 | 0.5362 | 0.417 | 1.5 |
| map-reduce | prose | small | 211 | 2 | 1.1361 | 1.0 | 1.0 |
| Fibonacci | csl | small | 114 | 4 | 0.9069 | 0.518 | 4.0 |
| Fibonacci | apl | small | 42 | 4 | 0.4211 | 0.191 | 4.0 |
| Fibonacci | lojban | small | 58 | 2 | 0.2084 | 0.264 | 2.0 |
| Fibonacci | prose | small | 220 | 0 | 0.0 | 1.0 | 0.0 |
| quicksort | csl | small | 167 | 2 | 1.489 | 0.607 | 2.0 |
| quicksort | apl | small | 57 | 3 | 0.6355 | 0.207 | 3.0 |
| quicksort | lojban | small | 92 | 2 | 0.7234 | 0.335 | 2.0 |
| quicksort | prose | small | 275 | 0 | 0.0 | 1.0 | 0.0 |
| binary search | csl | medium | 220 | 4 | 1.2809 | 0.884 | 4.0 |
| binary search | apl | medium | 45 | 5 | 1.3936 | 0.181 | 5.0 |
| binary search | lojban | medium | 107 | 3 | 2.2267 | 0.43 | 3.0 |
| binary search | prose | medium | 249 | 0 | 0.0 | 1.0 | 0.0 |
| bubble sort | csl | medium | 147 | 3 | 1.1372 | 0.665 | 3.0 |
| bubble sort | apl | medium | 30 | 5 | 0.6664 | 0.136 | 5.0 |
| bubble sort | lojban | medium | 99 | 3 | 1.6642 | 0.448 | 3.0 |
| bubble sort | prose | medium | 221 | 0 | 0.0 | 1.0 | 0.0 |
| map-reduce | csl | medium | 104 | 3 | 0.9882 | 0.493 | 1.5 |
| map-reduce | apl | medium | 26 | 3 | 0.4062 | 0.123 | 1.5 |
| map-reduce | lojban | medium | 88 | 3 | 0.5278 | 0.417 | 1.5 |
| map-reduce | prose | medium | 211 | 2 | 1.5422 | 1.0 | 1.0 |
| Fibonacci | csl | medium | 114 | 4 | 1.1333 | 0.518 | 4.0 |
| Fibonacci | apl | medium | 42 | 4 | 0.5489 | 0.191 | 4.0 |
| Fibonacci | lojban | medium | 58 | 2 | 0.415 | 0.264 | 2.0 |
| Fibonacci | prose | medium | 220 | 0 | 0.0 | 1.0 | 0.0 |
| quicksort | csl | medium | 167 | 2 | 1.6723 | 0.607 | 2.0 |
| quicksort | apl | medium | 57 | 5 | 1.306 | 0.207 | 5.0 |
| quicksort | lojban | medium | 92 | 2 | 0.912 | 0.335 | 2.0 |
| quicksort | prose | medium | 275 | 0 | 0.0 | 1.0 | 0.0 |
| binary search | csl | large | 220 | 4 | 1.2341 | 0.884 | 4.0 |
| binary search | apl | large | 45 | 6 | 1.5774 | 0.181 | 6.0 |
| binary search | lojban | large | 107 | 3 | 2.6033 | 0.43 | 3.0 |
| binary search | prose | large | 249 | 0 | 0.0 | 1.0 | 0.0 |
| bubble sort | csl | large | 147 | 4 | 0.8697 | 0.665 | 2.0 |
| bubble sort | apl | large | 30 | 6 | 1.0 | 0.136 | 3.0 |
| bubble sort | lojban | large | 99 | 3 | 2.1383 | 0.448 | 1.5 |
| bubble sort | prose | large | 221 | 2 | 1.375 | 1.0 | 1.0 |
| map-reduce | csl | large | 104 | 3 | 1.5869 | 0.493 | 1.5 |
| map-reduce | apl | large | 26 | 5 | 0.5034 | 0.123 | 2.5 |
| map-reduce | lojban | large | 88 | 3 | 0.7704 | 0.417 | 1.5 |
| map-reduce | prose | large | 211 | 2 | 1.3116 | 1.0 | 1.0 |
| Fibonacci | csl | large | 114 | 4 | 1.0712 | 0.518 | 2.0 |
| Fibonacci | apl | large | 42 | 6 | 1.0708 | 0.191 | 3.0 |
| Fibonacci | lojban | large | 58 | 2 | 0.1567 | 0.264 | 1.0 |
| Fibonacci | prose | large | 220 | 2 | 1.1658 | 1.0 | 1.0 |
| quicksort | csl | large | 167 | 3 | 1.0292 | 0.607 | 3.0 |
| quicksort | apl | large | 57 | 6 | 1.5632 | 0.207 | 6.0 |
| quicksort | lojban | large | 92 | 3 | 1.1779 | 0.335 | 3.0 |
| quicksort | prose | large | 275 | 0 | 0.0 | 1.0 | 0.0 |

## Summary: average compression vs prose (char-based)

| notation | avg char-compression |
|----------|---------------------:|
| csl | 0.633 |
| apl | 0.168 |
| lojban | 0.379 |
| prose | 1.000 |

## Mean NLL/token by notation + model

| notation | large | medium | small |
|----------|---:|---:|---:|
| csl | 1.158 | 1.242 | 1.074 |
| apl | 1.143 | 0.864 | 0.410 |
| lojban | 1.369 | 1.149 | 1.100 |
| prose | 0.770 | 0.308 | 0.227 |

## Reading the results

- **CSLv3 vs prose** : token-compression near or below 0.5 validates the density claim for spec-domain content.
- **APL vs prose** : typically 0.1-0.2 character-compression, very dense but opaque to humans + LLMs without APL training.
- **Lojban vs prose** : roughly 1.0, neither denser nor sparser ; Lojban is a natural-language construct and not a density-optimized notation.
- **CSLv3 positioning** : between the APL/BQN extreme and prose baseline. Optimized for human + LLM + compiler readability simultaneously, accepting modest character overhead vs APL for gains in all three audiences.

