package cslparser

// § CSLv3 OPT — DEAD CODE ELIMINATION (T27.d Session-8)
// I> remove ops whose results have zero uses AND no side-effects
// I> preserves : terminators + anything with side-effects (return/branch/call/
//                cslv3.effect.perform/refinement.assert/store)
// I> uses use-def-analysis when available ; else computes inline
// I> region-sensitive : an op's regions remain intact if the op itself is kept

import "core:fmt"

make_pass_dce :: proc() -> Pass {
    return Pass{
        name = "dce",
        kind = .Transform,
        run  = dce_run,
    }
}

dce_run :: proc(ctx: ^Pass_Ctx, m: ^Module) -> Pass_Stats {
    st: Pass_Stats
    st.ran = 1
    if m == nil do return st
    // Build use-def fresh : DCE can invalidate prior analysis
    ud := usedef_build(m)
    defer usedef_destroy(ud)

    for op in m.ops do dce_walk(op, ud, &st)
    if st.applied > 0 do st.note = fmt.tprintf("removed=%d", st.applied)
    return st
}

@(private="file")
dce_walk :: proc(op: ^Op, ud: ^Use_Def, st: ^Pass_Stats) {
    if op == nil do return
    for r in op.regions {
        if r == nil do continue
        for b in r.blocks {
            if b == nil do continue
            // Scan ops, filter out dead ones.
            new_ops := make([dynamic]^Op, 0, len(b.ops))
            for child in b.ops {
                // Terminators always kept — keep it as the final op.
                if op_is_terminator(child) {
                    append(&new_ops, child)
                    continue
                }
                if has_side_effects(child) {
                    append(&new_ops, child)
                    // Still recurse into its regions.
                    dce_walk(child, ud, st)
                    continue
                }
                // Pure op : if all its results are unused, drop.
                if all_results_unused(child, ud) {
                    st.applied += 1
                    continue
                }
                append(&new_ops, child)
                dce_walk(child, ud, st)
            }
            delete(b.ops)
            b.ops = new_ops
        }
    }
}

@(private="file")
all_results_unused :: proc(op: ^Op, ud: ^Use_Def) -> bool {
    if len(op.results) == 0 do return false   // no-result op : rely on side-effect check
    for r in op.results {
        if r == nil do continue
        if usedef_use_count(ud, r) > 0 do return false
    }
    return true
}

@(private="file")
has_side_effects :: proc(op: ^Op) -> bool {
    if op == nil do return false
    switch op.name {
    case OP_CALL, OP_EFF_PERFORM, OP_EFF_HANDLE, OP_REFINE,
         "cslv3.store", "cslv3.assume", OP_MATCH:
        return true
    }
    // Terminators technically have effects but are handled separately.
    return false
}
