package cslparser

// § CSLv3 OPT — SMT-INFORMED BRANCH PRUNING (T27.h Session-8)
// I> query Z3 : "is this cslv3.if's condition provably-true/false under
//    refinement context?" If so, replace with the taken-branch body.
// I> budget-bounded : ctx.fuel limits query-count (1 query per if-op)
// I> graceful-degrade : no-solver → skip all queries + note "no-solver"
// I> current condition extraction : only handles constant-bool conditions
//    (which constant-folding already handles). This pass becomes meaningful
//    when SMT-prune drops branches whose condition is non-constant but
//    provably-determined under refinements — a Session-9+ extension when
//    richer refinement-context is available.
// I> for now, this pass exercises the CLI wiring + records per-branch
//    stats ; actual pruning happens opportunistically for bool-const conds.

import "core:fmt"

make_pass_smt_prune :: proc() -> Pass {
    return Pass{
        name = "smt-prune",
        kind = .Transform,
        run  = smt_prune_run,
    }
}

smt_prune_run :: proc(ctx: ^Pass_Ctx, m: ^Module) -> Pass_Stats {
    st: Pass_Stats
    st.ran = 1
    if m == nil do return st

    solver_ok := ctx.z3_path != "" || ctx.cvc5_path != ""
    if !solver_ok {
        st.note = "no-solver"
        return st
    }

    for op in m.ops do prune_walk(ctx, op, &st)
    if st.applied > 0 do st.note = fmt.tprintf("pruned=%d skipped=%d", st.applied, st.skipped)
    return st
}

@(private="file")
prune_walk :: proc(ctx: ^Pass_Ctx, op: ^Op, st: ^Pass_Stats) {
    if op == nil do return
    for r in op.regions {
        if r == nil do continue
        for b in r.blocks {
            if b == nil do continue
            for child in b.ops {
                try_prune_if(ctx, child, st)
            }
            // Recurse
            for child in b.ops do prune_walk(ctx, child, st)
        }
    }
}

@(private="file")
try_prune_if :: proc(ctx: ^Pass_Ctx, op: ^Op, st: ^Pass_Stats) {
    if op == nil || op.name != OP_IF do return
    if len(op.operands) < 1 || op.operands[0] == nil do return
    cond := op.operands[0]

    // Static : if cond is a const bool, pick the branch.
    if cond.def_op != nil && cond.def_op.name == OP_CONST {
        if a, ok := op_get_attr(cond.def_op, "value"); ok && a.kind == .Bool {
            if a.bool_v {
                // keep then, drop else
                if len(op.regions) >= 2 {
                    op.regions[1].blocks = nil
                }
                st.applied += 1
            } else {
                if len(op.regions) >= 1 {
                    op.regions[0].blocks = nil
                }
                st.applied += 1
            }
            return
        }
    }

    // SMT query path : build a tiny script "is cond always-false under refinements?"
    // For the first-iteration, we skip dynamic queries when ctx.fuel==0 and
    // record them as skipped to expose wiring.
    if ctx.fuel > 0 {
        st.skipped += 1   // record that we considered but didn't prune
        ctx.fuel -= 1
    }
}
