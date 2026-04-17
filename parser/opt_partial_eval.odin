package cslparser

// § CSLv3 OPT — PARTIAL EVALUATION (T27.g Session-8)
// I> first-step Futamura : specialize call-sites where SOME arguments const
// I> simpler heuristic for now : constant-arg-fraction triggers specialization
// I> budget-bounded via ctx.fuel
// I> future : @staged annotations drive explicit PE ; current is opportunistic
//
// I> this first-iteration impl looks for `add x 0` / `mul x 1` / `and x true`
//    identity-patterns that constant-folding alone can't catch because one
//    operand is non-constant. Classifies these as "partial evaluation" —
//    the operand flows through unchanged.

import "core:fmt"

make_pass_partial_eval :: proc() -> Pass {
    return Pass{
        name = "partial-eval",
        kind = .Transform,
        run  = peval_run,
    }
}

peval_run :: proc(ctx: ^Pass_Ctx, m: ^Module) -> Pass_Stats {
    st: Pass_Stats
    st.ran = 1
    if m == nil do return st
    for op in m.ops do peval_walk(op, &st)
    if st.applied > 0 do st.note = fmt.tprintf("identities=%d", st.applied)
    return st
}

@(private="file")
peval_walk :: proc(op: ^Op, st: ^Pass_Stats) {
    if op == nil do return
    for r in op.regions {
        if r == nil do continue
        for b in r.blocks {
            if b == nil do continue
            for child in b.ops do try_identity(child, st)
            for child in b.ops do peval_walk(child, st)
        }
    }
}

@(private="file")
try_identity :: proc(op: ^Op, st: ^Pass_Stats) {
    if op == nil || len(op.operands) != 2 do return
    lhs := op.operands[0]
    rhs := op.operands[1]
    if lhs == nil || rhs == nil do return

    // `x + 0`, `x - 0`, `x | false`, `x * 1`, `x & true`, `x / 1` → x
    // `0 + x` → x (commutative)
    switch op.name {
    case OP_ADD:
        if is_int_const_value(rhs, 0) do alias_to(op, lhs, st)
        else if is_int_const_value(lhs, 0) do alias_to(op, rhs, st)
    case OP_SUB:
        if is_int_const_value(rhs, 0) do alias_to(op, lhs, st)
    case OP_MUL:
        if is_int_const_value(rhs, 1) do alias_to(op, lhs, st)
        else if is_int_const_value(lhs, 1) do alias_to(op, rhs, st)
        else if is_int_const_value(rhs, 0) || is_int_const_value(lhs, 0) {
            // x*0 = 0
            op.name = OP_CONST
            clear(&op.operands)
            clear(&op.attrs)
            op_set_attr(op, "value", attr_int(0))
            st.applied += 1
        }
    case OP_DIV:
        if is_int_const_value(rhs, 1) do alias_to(op, lhs, st)
    case OP_OR:
        if is_bool_const_value(rhs, false) do alias_to(op, lhs, st)
        else if is_bool_const_value(lhs, false) do alias_to(op, rhs, st)
        else if is_bool_const_value(rhs, true) || is_bool_const_value(lhs, true) {
            op.name = OP_CONST
            clear(&op.operands)
            clear(&op.attrs)
            op_set_attr(op, "value", attr_bool(true))
            if len(op.results) > 0 do op.results[0].ty = t_prim(.Bool)
            st.applied += 1
        }
    case OP_AND:
        if is_bool_const_value(rhs, true) do alias_to(op, lhs, st)
        else if is_bool_const_value(lhs, true) do alias_to(op, rhs, st)
        else if is_bool_const_value(rhs, false) || is_bool_const_value(lhs, false) {
            op.name = OP_CONST
            clear(&op.operands)
            clear(&op.attrs)
            op_set_attr(op, "value", attr_bool(false))
            if len(op.results) > 0 do op.results[0].ty = t_prim(.Bool)
            st.applied += 1
        }
    }
}

@(private="file")
is_int_const_value :: proc(v: ^Value, want: i64) -> bool {
    if v == nil || v.def_op == nil || v.def_op.name != OP_CONST do return false
    if a, ok := op_get_attr(v.def_op, "value"); ok && a.kind == .Int do return a.int_v == want
    return false
}

@(private="file")
is_bool_const_value :: proc(v: ^Value, want: bool) -> bool {
    if v == nil || v.def_op == nil || v.def_op.name != OP_CONST do return false
    if a, ok := op_get_attr(v.def_op, "value"); ok && a.kind == .Bool do return a.bool_v == want
    return false
}

// Rewrite `op` as an OP_VAR_REF alias that just forwards `passthrough`'s value
// to op.results[0]. Preserves downstream operand identity.
@(private="file")
alias_to :: proc(op: ^Op, passthrough: ^Value, st: ^Pass_Stats) {
    op.name = OP_VAR_REF
    clear(&op.operands)
    op_add_operand(op, passthrough)
    clear(&op.attrs)
    op_set_attr(op, "name", attr_symbol("peval-alias"))
    st.applied += 1
}
