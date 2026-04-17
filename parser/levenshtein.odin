package cslparser

// § P2.1 Session-13 : Wagner-Fischer Levenshtein distance in Odin.
// I> replaces : Rust `levenshtein` crate dep in lsp/server/ (D14)
// I> 2-row dp ← O(m·n) time + O(min(m,n)) space
// I> unicode-aware : iterates runes, not bytes
// I> used-by : code-action "did you mean"-style suggestions
//
// API :
//   levenshtein(a, b)             -> u32  (full edit-distance)
//   levenshtein_limit(a, b, max)  -> u32  (early-exit ; returns max+1 if exceeded)
//
// CLI :
//   parser.exe --distance <a> <b>
//     prints integer distance to stdout ; exits 0.

import "core:unicode/utf8"

levenshtein :: proc(a, b: string) -> u32 {
    // Convert to rune slices so edit-ops are character-level, not byte-level.
    ra := utf8.string_to_runes(a, context.temp_allocator)
    rb := utf8.string_to_runes(b, context.temp_allocator)
    // Swap so the shorter string drives the inner dimension ← minimises memory.
    if len(ra) < len(rb) { ra, rb = rb, ra }
    n := len(ra)
    m := len(rb)
    if m == 0 do return u32(n)

    // Two-row rolling buffer ; prev[j] = dp[i-1][j], cur[j] = dp[i][j].
    prev := make([]u32, m + 1, context.temp_allocator)
    cur  := make([]u32, m + 1, context.temp_allocator)
    for j in 0 ..= m do prev[j] = u32(j)

    for i in 1 ..= n {
        cur[0] = u32(i)
        for j in 1 ..= m {
            cost: u32 = 0 if ra[i-1] == rb[j-1] else 1
            // min(insert, delete, substitute)
            ins := cur[j-1] + 1
            del := prev[j] + 1
            sub := prev[j-1] + cost
            best := ins
            if del < best do best = del
            if sub < best do best = sub
            cur[j] = best
        }
        prev, cur = cur, prev
    }
    return prev[m]
}

// levenshtein_limit — early-exit when any row's min exceeds `max`.
// Returns `max + 1` as a sentinel if the limit is exceeded. Useful for
// ranked-suggest code-paths : we only care that the distance is ≤ N.
levenshtein_limit :: proc(a, b: string, max: u32) -> u32 {
    ra := utf8.string_to_runes(a, context.temp_allocator)
    rb := utf8.string_to_runes(b, context.temp_allocator)
    if len(ra) < len(rb) { ra, rb = rb, ra }
    n := len(ra)
    m := len(rb)
    // length-difference alone already exceeds the limit : short-circuit.
    diff := u32(n - m)
    if diff > max do return max + 1
    if m == 0 do return u32(n)

    prev := make([]u32, m + 1, context.temp_allocator)
    cur  := make([]u32, m + 1, context.temp_allocator)
    for j in 0 ..= m do prev[j] = u32(j)

    for i in 1 ..= n {
        cur[0] = u32(i)
        row_min := cur[0]
        for j in 1 ..= m {
            cost: u32 = 0 if ra[i-1] == rb[j-1] else 1
            ins := cur[j-1] + 1
            del := prev[j] + 1
            sub := prev[j-1] + cost
            best := ins
            if del < best do best = del
            if sub < best do best = sub
            cur[j] = best
            if best < row_min do row_min = best
        }
        if row_min > max do return max + 1
        prev, cur = cur, prev
    }
    return prev[m]
}

// ranked_candidates — given a query and a list of candidates, return them
// sorted by (distance ascending, input-order stable). Used by code-action
// "did you mean X?" suggestions. Returns (candidate, distance) pairs.
Ranked_Suggestion :: struct {
    candidate: string,
    distance:  u32,
}

ranked_candidates :: proc(query: string, candidates: []string,
                          max_dist: u32 = 3,
                          allocator := context.allocator) -> []Ranked_Suggestion {
    context.allocator = allocator
    out := make([dynamic]Ranked_Suggestion, 0, len(candidates))
    for c in candidates {
        d := levenshtein_limit(query, c, max_dist)
        if d <= max_dist {
            append(&out, Ranked_Suggestion{candidate = c, distance = d})
        }
    }
    // Stable insertion-sort on distance (n is small for suggestion lists)
    for i in 1 ..< len(out) {
        x := out[i]
        j := i
        for j > 0 && out[j-1].distance > x.distance {
            out[j] = out[j-1]
            j -= 1
        }
        out[j] = x
    }
    return out[:]
}
