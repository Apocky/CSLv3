# C4 — Reasoning Block Trace (English)

The agent's reasoning substrate follows a five-part structure inspired
by problem-solving methodology: Problem, Decomposition, Trace,
Synthesis, and Check. This trace is an example chain-of-thought for
a parser-speed regression.

## Problem

There is a parser-speed regression after the recent lexer rewrite.
The goal of this investigation is to restore the ten-thousand-lines-
per-second baseline throughput we measured before the rewrite.

## Decomposition

We break the slowdown into three candidate causes: it could be heap
allocation overhead that increased, it could be the dispatch pattern
in the main tokenizer switch becoming more expensive, or it could be
rune-decoding in the UTF-8 handling path becoming slower.

## Trace

We profile heap allocation first. The profiler shows allocation volume
is flat compared to before, so allocation is not the culprit.

We then profile dispatch. The switch appears about eight percent worse
than before, which is a small regression but not big enough to explain
the total slowdown on its own.

Finally we micro-benchmark rune decoding. The decode path is forty
percent slower than before. This is the dominant cause.

## Synthesis

The primary culprit is the rune-decode path. The fix is to add a fast
path for ASCII characters that caches the UTF-8 width calculation, so
single-byte characters skip the general decoder entirely.

## Check

After the fix, throughput is restored to within two percent of the
original baseline. An edge case: input that is heavily unicode remains
about fifteen percent slower than the baseline. That is an accepted
regression for the ASCII optimization; a second-phase SIMD decoder
could address it later.
