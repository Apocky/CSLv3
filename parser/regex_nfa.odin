package cslparser

// § A8 Session-15 : Pike-VM execution engine.
//
// I> Per Cox 2007 : maintain two thread-lists (current + next). At each
//    input rune, step every current thread ; epsilon-style instructions
//    (JMP / SPLIT / SAVE / ANCHOR) execute immediately and schedule
//    additional threads. Consuming instructions (CHAR / CLASS / ANY /
//    BACKREF) advance one rune and land on the next-list.
// I> Dedupe by pc : at most one thread per pc survives per step →
//    O(m) active threads worst-case, O(mn) total.
// I> Capture slots : mutable array copied on SAVE (so parallel threads
//    don't clobber each other's captures).
// I> Max states + max backref size capped → DoS-safe.

// ------------------------- execution types -------------------------

// Captures is a mutable array of 2*n_groups positions. Index 0..1 are
// whole-match start/end. Positions are BYTE offsets in the input.
Re_Captures :: [dynamic]int   // -1 means "not captured"

// A running thread.
@(private="file")
Re_Thread :: struct {
    pc:   int,
    caps: Re_Captures,
}

// Match result returned by the public API.
Regex_Match :: struct {
    ok:     bool,
    start:  int,                       // byte offset into input (whole match)
    end:    int,                       // byte offset ; end > start iff matched
    groups: []Regex_Group,             // groups[0] = whole match
}

Regex_Group :: struct {
    start, end: int,                   // byte offsets ; -1 if not captured
    text:       string,                // slice into input
    name:       string,                // empty if unnamed
}

// ------------------------- main driver -------------------------

// Anchored match : the regex must match starting exactly at `start_byte`.
regex_nfa_run :: proc(prog: ^Regex_Program, input: string, start_byte: int,
                      allocator := context.allocator) -> Regex_Match {
    context.allocator = allocator
    m := Regex_Match{ ok = false, start = -1, end = -1 }

    curr := make([dynamic]Re_Thread, 0, 16)
    next := make([dynamic]Re_Thread, 0, 16)
    // Dedupe : seen[pc] = generation stamp. We reset per input-step.
    n_inst := len(prog.code)
    seen_curr := make([]int, n_inst)
    seen_next := make([]int, n_inst)
    for i in 0 ..< n_inst { seen_curr[i] = -1; seen_next[i] = -1 }
    defer delete(seen_curr)
    defer delete(seen_next)

    step := 0

    initial_caps := make(Re_Captures, 2 * max(1, prog.n_groups + 1))
    for i in 0 ..< len(initial_caps) do initial_caps[i] = -1

    add_thread(&curr, prog, 0, initial_caps, input, start_byte, seen_curr, step)

    best_match: Re_Captures = nil
    best_ok := false

    i := start_byte
    for i <= len(input) {
        // Consume one rune at position i.
        r, rn := utf8_decode(input, i)
        next_i := i + rn
        // For each thread, the "consuming" ops are CHAR/CLASS/ANY/BACKREF.
        step += 1
        step_loop: for t in curr {
            ins := prog.code[t.pc]
            switch ins.op {
            case .Char:
                if rn > 0 && r == ins.rune_val {
                    new_caps := clone_caps(t.caps)
                    add_thread(&next, prog, t.pc + 1, new_caps, input, next_i, seen_next, step)
                }
            case .Class:
                if rn > 0 && class_contains(ins.class, r) {
                    new_caps := clone_caps(t.caps)
                    add_thread(&next, prog, t.pc + 1, new_caps, input, next_i, seen_next, step)
                }
            case .Any_Char:
                if rn > 0 && r != '\n' {
                    new_caps := clone_caps(t.caps)
                    add_thread(&next, prog, t.pc + 1, new_caps, input, next_i, seen_next, step)
                }
            case .Backref:
                // Look up captured text of this group in THIS thread.
                g := ins.backref
                if g <= 0 || g > prog.n_groups { continue }
                gs := t.caps[2*g]
                ge := t.caps[2*g + 1]
                if gs < 0 || ge < 0 { continue }
                cap_text := input[gs:ge]
                if len(cap_text) == 0 {
                    // zero-width backref : pass through
                    new_caps := clone_caps(t.caps)
                    add_thread(&next, prog, t.pc + 1, new_caps, input, i, seen_next, step)
                    continue
                }
                if i + len(cap_text) <= len(input) && input[i:i+len(cap_text)] == cap_text {
                    new_caps := clone_caps(t.caps)
                    add_thread(&next, prog, t.pc + 1, new_caps, input, i + len(cap_text),
                               seen_next, step)
                }
            case .Match:
                // Overwrite on every MATCH reached this step : higher-
                // priority threads (earlier in `curr`) represent greedier
                // paths, and later input-steps that still have live threads
                // can yield even longer matches. Per Pike-VM : after MATCH
                // fires, remaining lower-priority threads in THIS step are
                // killed ; higher-priority threads already processed keep
                // their scheduled extensions in `next`.
                if best_match != nil do delete(best_match)
                best_match = clone_caps(t.caps)
                best_ok = true
                break step_loop
            case .Jmp, .Split, .Save, .Anchor:
                // epsilon ops : shouldn't appear in curr after add_thread
                // processed them. Safe to ignore.
            }
        }

        // Swap curr ↔ next ; clear.
        // Free old curr cap arrays.
        for t in curr do if t.caps != nil do delete(t.caps)
        clear(&curr)
        curr, next = next, curr
        for k in 0 ..< n_inst do seen_curr[k] = seen_next[k]
        for k in 0 ..< n_inst do seen_next[k] = -1

        // If no threads remain OR we consumed all input → stop.
        if len(curr) == 0 do break
        if rn == 0 do break       // already processed the EOF epsilon-step
        i = next_i
    }

    // Final pass : at end-of-input, some threads may land on MATCH via
    // SAVE/EOS anchor epsilons. Process them.
    step += 1
    for t in curr {
        ins := prog.code[t.pc]
        if ins.op == .Match && !best_ok {
            best_match = clone_caps(t.caps)
            best_ok = true
        }
    }
    // Free remaining caps (except best_match ← transferred).
    for t in curr do if t.caps != nil do delete(t.caps)
    delete(curr)
    delete(next)

    if !best_ok {
        m.ok = false
        return m
    }

    // Materialise the Match / groups.
    m.ok = true
    m.start = best_match[0]
    m.end   = best_match[1]
    n_groups := prog.n_groups + 1
    groups := make([]Regex_Group, n_groups)
    for g in 0 ..< n_groups {
        s := best_match[2*g]
        e := best_match[2*g + 1]
        name := ""
        if g < len(prog.group_names) do name = prog.group_names[g]
        if s >= 0 && e >= 0 && s <= e {
            groups[g] = Regex_Group{ start = s, end = e, text = input[s:e], name = name }
        } else {
            groups[g] = Regex_Group{ start = -1, end = -1, text = "", name = name }
        }
    }
    m.groups = groups
    delete(best_match)
    return m
}

@(private="file")
clone_caps :: proc(src: Re_Captures) -> Re_Captures {
    d := make(Re_Captures, len(src))
    for i in 0 ..< len(src) do d[i] = src[i]
    return d
}

// add_thread : schedule a thread at `pc`, running through epsilon-ops
// (JMP/SPLIT/SAVE/ANCHOR) in place. Terminal states (CHAR/CLASS/ANY/
// BACKREF/MATCH) are appended to `list`.
@(private="file")
add_thread :: proc(list: ^[dynamic]Re_Thread, prog: ^Regex_Program,
                   pc: int, caps: Re_Captures,
                   input: string, pos: int,
                   seen: []int, step: int) {
    if pc < 0 || pc >= len(prog.code) do return
    if seen[pc] == step {
        // Already scheduled this pc in this step ; free the duplicate caps.
        delete(caps)
        return
    }
    seen[pc] = step

    ins := prog.code[pc]
    switch ins.op {
    case .Jmp:
        add_thread(list, prog, ins.x, caps, input, pos, seen, step)
    case .Split:
        new_caps_b := clone_caps(caps)
        add_thread(list, prog, ins.x, caps, input, pos, seen, step)
        add_thread(list, prog, ins.y, new_caps_b, input, pos, seen, step)
    case .Save:
        new_caps := clone_caps(caps)
        if ins.slot < len(new_caps) do new_caps[ins.slot] = pos
        delete(caps)
        add_thread(list, prog, pc + 1, new_caps, input, pos, seen, step)
    case .Anchor:
        if anchor_match(ins.anchor, input, pos) {
            add_thread(list, prog, pc + 1, caps, input, pos, seen, step)
        } else {
            delete(caps)
        }
    case .Char, .Class, .Any_Char, .Backref, .Match:
        append(list, Re_Thread{ pc = pc, caps = caps })
    }
}

@(private="file")
anchor_match :: proc(a: Anchor_Kind, input: string, pos: int) -> bool {
    switch a {
    case .BOS:
        if pos == 0 do return true
        // multiline-lite : also after \n (not currently exposed as a flag ;
        // follow JS convention : ^ matches only at string start).
        return false
    case .EOS:
        return pos == len(input)
    case .BOW:
        return is_word_boundary(input, pos)
    case .NBOW:
        return !is_word_boundary(input, pos)
    }
    return false
}

@(private="file")
is_word_boundary :: proc(input: string, pos: int) -> bool {
    prev_word := false
    next_word := false
    if pos > 0 {
        pr, _ := utf8_prev(input, pos)
        prev_word = is_word_rune(pr)
    }
    if pos < len(input) {
        nr, _ := utf8_decode(input, pos)
        next_word = is_word_rune(nr)
    }
    return prev_word != next_word
}

@(private="file")
is_word_rune :: #force_inline proc(r: rune) -> bool {
    return is_ascii_word(r) || is_letter(r)
}

// ---------- character-class membership ----------

class_contains :: proc(cc: ^Char_Class, r: rune) -> bool {
    hit := false
    // explicit ranges
    for rr in cc.ranges {
        if r >= rr.lo && r <= rr.hi { hit = true; break }
    }
    if !hit {
        if .Ascii_Digit     in cc.flags && is_ascii_digit(r)      do hit = true
        if .Not_Ascii_Digit in cc.flags && !is_ascii_digit(r)     do hit = true
        if .Ascii_Space     in cc.flags && is_ascii_space(r)      do hit = true
        if .Not_Ascii_Space in cc.flags && !is_ascii_space(r)     do hit = true
        if .Ascii_Word      in cc.flags && is_ascii_word(r)       do hit = true
        if .Not_Ascii_Word  in cc.flags && !is_ascii_word(r)      do hit = true
        if .Unicode_Letter  in cc.flags && is_letter(r)           do hit = true
        if .Unicode_Number  in cc.flags && is_number(r)           do hit = true
        if .Unicode_Punct   in cc.flags && is_punct(r)            do hit = true
        if .Unicode_Symbol  in cc.flags && is_symbol(r)           do hit = true
    }
    if cc.negated do return !hit
    return hit
}
