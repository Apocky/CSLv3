# C1 — Sorting Algorithm Specification (English)

## Goal

This specification describes an in-place comparison sort implementation.
The goal is to provide a sorting routine with predictable worst-case
time complexity and no heap allocations during execution. The algorithm
uses a divide-and-conquer strategy based on merge sort, with an
insertion-sort fallback for small subarrays.

## Data

The sorter operates on a dynamically sized array of 32-bit signed
integers. The comparison function takes two such integers and returns
a boolean indicating whether the first argument is ordered before the
second.

## Operations

The top-level `sort` operation takes a mutable reference to the array
and a comparison function as arguments. It returns a boolean indicating
success. A precondition is that the array pointer must not be null.

The `merge-sort` helper performs the recursive split on a subarray
bounded by a low and a high index. It recursively sorts the left and
right halves, then calls `merge` to combine them.

The `merge` operation takes the array, a low index, a midpoint index,
and a high index. It assumes the two halves are already sorted and
merges them in order.

## Invariants

After `sort` returns, for every adjacent pair of elements in the array,
the comparison function must report them in non-decreasing order. The
algorithm must run in time bounded by n log n comparisons, and it must
use no more than linear additional auxiliary space (for the merge
buffer).

## Tests

Case 1: sorting an empty array must return true without touching any
memory. Case 2: sorting a single-element array is a no-op that also
returns true. The edge case we care about is sorting an already-reversed
input, which exercises the worst path through the recursion.

## Anti-patterns

Recursing on very small subarrays is a known inefficiency: the constant
overhead of the recursive call exceeds the cost of simply insertion-
sorting the small fragment. The preferred approach is to fall back to
insertion sort when a subarray becomes shorter than 16 elements.
