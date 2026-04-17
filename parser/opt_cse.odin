package cslparser

// § CSLv3 OPT — COMMON SUBEXPRESSION ELIMINATION (T27.e Session-8)
// I> hash-cons pure ops within a block (simple single-block CSE for now)
// I> key = op.name + operands[]-value-ids + sorted-attr-kv
// I> on match : rewrite second-op into alias of first (OP_VAR_REF is-not-used —
//               instead we just remap downstream uses in this block via
//               rebind-operands — pure + same-block only keeps correctness)
// I> preserves : nothing (rewrites use-def) ; runs after usedef analysis

import "core:fmt"
import "core:slice"
import "core:strings"

@(private="file") cse_requires := [?]string{"usedef"}

make_pass_cse :: proc() -> Pass {
    return Pass{
        name = "cse",
        kind = .Transform,
        requires = cse_requires[:],
        run  = cse_run,
    }
}

cse_run :: proc(ctx: ^Pass_Ctx, m: ^Module) -> Pass_Stats {
    st: Pass_Stats
    st.ran = 1
    if m == nil do return st
    for op in m.ops do cse_walk(op, &st)
    if st.applied > 0 do st.note = fmt.tprintf("merged=%d", st.applied)
    return st
}

@(private="file")
cse_walk :: proc(op: ^Op, st: ^Pass_Stats) {
    if op == nil do return
    for r in op.regions {
        if r == nil do continue
        for b in r.blocks {
            if b == nil do continue
            cse_block(b, st)
            for child in b.ops do cse_walk(child, st)
        }
    }
}

// Within a single block, fold duplicate pure ops.
@(private="file")
cse_block :: proc(b: ^Block, st: ^Pass_Stats) {
    seen: map[string]^Op
    defer delete(seen)

    for child, i in b.ops {
        if !is_pure_cse_candidate(child) do continue
        key := op_cse_key(child)
        if prev, have := seen[key]; have {
            // Rewrite subsequent uses of child.results[0] to prev.results[0].
            if len(child.results) != len(prev.results) do continue
            rewritten := false
            for k in 0..<len(child.results) {
                if child.results[k] == nil || prev.results[k] == nil do continue
                if rewire_uses_in_block(b, child.results[k], prev.results[k], i) {
                    rewritten = true
                }
            }
            if rewritten do st.applied += 1
            continue
        }
        seen[key] = child
    }
}

@(private="file")
is_pure_cse_candidate :: proc(op: ^Op) -> bool {
    if op == nil do return false
    if len(op.results) == 0 do return false
    if len(op.regions) > 0 do return false   // don't CSE ops with nested regions
    switch op.name {
    case OP_ADD, OP_SUB, OP_MUL,
         OP_EQ, OP_NEQ, OP_LT, OP_LE, OP_GT, OP_GE,
         OP_AND, OP_OR, OP_NOT,
         OP_CONST, OP_PROJ, OP_COMP_OF, OP_COMP_AND, OP_COMP_THAT_IS:
        return true
    }
    return false
}

@(private="file")
op_cse_key :: proc(op: ^Op) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, op.name)
    strings.write_byte(&sb, '|')
    for o in op.operands {
        if o == nil do strings.write_string(&sb, "nil,")
        else do strings.write_string(&sb, fmt.tprintf("%%%d,", o.id))
    }
    strings.write_byte(&sb, '|')
    // attrs : sorted key order
    if len(op.attrs) > 0 {
        keys := make([dynamic]string, 0, len(op.attrs))
        defer delete(keys)
        for k in op.attrs do append(&keys, k)
        slice.sort(keys[:])
        for k in keys {
            strings.write_string(&sb, fmt.tprintf("%s=%s;", k, attr_repr(op.attrs[k])))
        }
    }
    return strings.to_string(sb)
}

// Replace all uses of `old` with `new` for operands in ops AFTER index `from_idx`
// in this block's op list. Returns true on any rewrite.
@(private="file")
rewire_uses_in_block :: proc(b: ^Block, old, new: ^Value, from_idx: int) -> bool {
    changed := false
    for i := from_idx; i < len(b.ops); i += 1 {
        op := b.ops[i]
        if op == nil do continue
        for j in 0..<len(op.operands) {
            if op.operands[j] == old {
                op.operands[j] = new
                changed = true
            }
        }
    }
    return changed
}
