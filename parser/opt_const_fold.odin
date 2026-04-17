package cslparser

// § CSLv3 OPT — CONSTANT FOLDING (T27.c Session-8)
// I> fold arithmetic + comparison ops when all-operands are Int/Bool constants
// I> also fold (not true) → false ; (and const const) ; (or const const)
// I> iterative : applies until no-change within a single call
// I> preserves : nothing (creates new OP_CONST ops ; replaces uses)

import "core:fmt"

make_pass_const_fold :: proc() -> Pass {
    return Pass{
        name = "const-fold",
        kind = .Transform,
        run  = const_fold_run,
    }
}

const_fold_run :: proc(ctx: ^Pass_Ctx, m: ^Module) -> Pass_Stats {
    st: Pass_Stats
    st.ran = 1
    if m == nil do return st
    changed := true
    iters := 0
    for changed && iters < 16 {
        changed = false
        iters += 1
        for op in m.ops do changed = fold_walk(op, &st) || changed
    }
    if st.applied > 0 do st.note = fmt.tprintf("iters=%d", iters)
    return st
}

@(private="file")
fold_walk :: proc(op: ^Op, st: ^Pass_Stats) -> bool {
    if op == nil do return false
    changed := false
    for r in op.regions {
        if r == nil do continue
        for b in r.blocks {
            if b == nil do continue
            // walk in reverse so replacing in-place doesn't skip neighbors
            for i := 0; i < len(b.ops); i += 1 {
                child := b.ops[i]
                if try_fold_op(b, i, child) {
                    st.applied += 1
                    changed = true
                }
                // Recurse into child's sub-regions
                changed = fold_walk(child, st) || changed
            }
        }
    }
    return changed
}

// Attempt to fold `op` in-place within `b.ops[idx]`. If the op's operands are
// all known constants and the op is a foldable arithmetic/compare/bool op,
// rewrite `op` into an OP_CONST carrying the computed value. Returns true
// when a fold occurred.
@(private="file")
try_fold_op :: proc(b: ^Block, idx: int, op: ^Op) -> bool {
    if op == nil do return false
    if !is_foldable_op(op.name) do return false
    if len(op.operands) == 0 do return false
    // Every operand must come from an OP_CONST op with a known numeric/bool value
    lhs_attr, lhs_ok := operand_const(op.operands[0])
    if !lhs_ok do return false

    switch op.name {
    case OP_NOT:
        if lhs_attr.kind != .Bool do return false
        return replace_with_bool(op, !lhs_attr.bool_v)

    case OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD:
        if len(op.operands) != 2 do return false
        rhs_attr, rhs_ok := operand_const(op.operands[1])
        if !rhs_ok do return false
        if lhs_attr.kind != .Int || rhs_attr.kind != .Int do return false
        if (op.name == OP_DIV || op.name == OP_MOD) && rhs_attr.int_v == 0 do return false
        v := apply_int_op(op.name, lhs_attr.int_v, rhs_attr.int_v)
        return replace_with_int(op, v)

    case OP_EQ, OP_NEQ, OP_LT, OP_LE, OP_GT, OP_GE:
        if len(op.operands) != 2 do return false
        rhs_attr, rhs_ok := operand_const(op.operands[1])
        if !rhs_ok do return false
        if lhs_attr.kind == .Int && rhs_attr.kind == .Int {
            return replace_with_bool(op, apply_int_cmp(op.name, lhs_attr.int_v, rhs_attr.int_v))
        }
        if lhs_attr.kind == .Bool && rhs_attr.kind == .Bool {
            if op.name == OP_EQ  do return replace_with_bool(op, lhs_attr.bool_v == rhs_attr.bool_v)
            if op.name == OP_NEQ do return replace_with_bool(op, lhs_attr.bool_v != rhs_attr.bool_v)
        }
        return false

    case OP_AND, OP_OR:
        if len(op.operands) != 2 do return false
        rhs_attr, rhs_ok := operand_const(op.operands[1])
        if !rhs_ok do return false
        if lhs_attr.kind != .Bool || rhs_attr.kind != .Bool do return false
        v := (lhs_attr.bool_v && rhs_attr.bool_v) if op.name == OP_AND else
             (lhs_attr.bool_v || rhs_attr.bool_v)
        return replace_with_bool(op, v)
    }
    _ = b
    _ = idx
    return false
}

@(private="file")
is_foldable_op :: proc(n: string) -> bool {
    switch n {
    case OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD,
         OP_EQ, OP_NEQ, OP_LT, OP_LE, OP_GT, OP_GE,
         OP_AND, OP_OR, OP_NOT:
        return true
    }
    return false
}

@(private="file")
operand_const :: proc(v: ^Value) -> (Attr, bool) {
    if v == nil || v.def_op == nil do return Attr{}, false
    if v.def_op.name != OP_CONST do return Attr{}, false
    a, ok := op_get_attr(v.def_op, "value")
    if !ok do return Attr{}, false
    return a, true
}

@(private="file")
apply_int_op :: proc(name: string, a, b: i64) -> i64 {
    switch name {
    case OP_ADD: return a + b
    case OP_SUB: return a - b
    case OP_MUL: return a * b
    case OP_DIV: return a / b
    case OP_MOD: return a % b
    }
    return 0
}

@(private="file")
apply_int_cmp :: proc(name: string, a, b: i64) -> bool {
    switch name {
    case OP_EQ:  return a == b
    case OP_NEQ: return a != b
    case OP_LT:  return a <  b
    case OP_LE:  return a <= b
    case OP_GT:  return a >  b
    case OP_GE:  return a >= b
    }
    return false
}

// Rewrite `op` in place as an OP_CONST with int-value `v`. Preserves op's
// result-Value identity so any existing uses remain intact.
@(private="file")
replace_with_int :: proc(op: ^Op, v: i64) -> bool {
    op.name = OP_CONST
    clear(&op.operands)
    // keep existing result[0] but clear attrs + reset
    clear(&op.attrs)
    op_set_attr(op, "value", attr_int(v))
    return true
}

@(private="file")
replace_with_bool :: proc(op: ^Op, v: bool) -> bool {
    op.name = OP_CONST
    clear(&op.operands)
    clear(&op.attrs)
    op_set_attr(op, "value", attr_bool(v))
    // also flip result-type to Bool
    if len(op.results) > 0 && op.results[0] != nil {
        op.results[0].ty = t_prim(.Bool)
    }
    return true
}
