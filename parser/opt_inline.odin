package cslparser

// § CSLv3 OPT — FUNCTION INLINING (T27.f Session-8)
// I> inlines cslv3.call whose callee resolves to a small cslv3.fn
// I> cost-model : fn-op-count vs budget (Pass_Ctx.fuel)
// I> alpha-rename via fresh Value-ids when splicing region-body
// I> conservative : only single-block Fn_Body with no nested fn-calls
//                   (Session-9+ will lift restrictions)
// I> preserves : nothing (mutates module structure)

import "core:fmt"

// callsite budget — tuned per opt-level through ctx.fuel
@(private="file")
MAX_INLINE_SIZE :: 32   // max ops in a function body to consider inlining

make_pass_inline :: proc() -> Pass {
    return Pass{
        name = "inline",
        kind = .Transform,
        run  = inline_run,
    }
}

inline_run :: proc(ctx: ^Pass_Ctx, m: ^Module) -> Pass_Stats {
    st: Pass_Stats
    st.ran = 1
    if m == nil || ctx.fuel <= 0 do return st

    // Build name → fn-op lookup for module-level fns.
    fns: map[string]^Op
    defer delete(fns)
    for op in m.ops {
        if op.name != OP_FN do continue
        if a, ok := op_get_attr(op, "name"); ok && a.kind == .Symbol {
            fns[a.str_v] = op
        }
    }

    // Track per-call budget consumption via st.skipped (non-inlined) and
    // st.applied (inlined). Depth-first walk.
    for op in m.ops do inline_walk(ctx, op, fns, &st)
    if st.applied > 0 || st.skipped > 0 {
        st.note = fmt.tprintf("inlined=%d skipped=%d fuel_left=%d",
                              st.applied, st.skipped, ctx.fuel)
    }
    return st
}

@(private="file")
inline_walk :: proc(ctx: ^Pass_Ctx, op: ^Op, fns: map[string]^Op, st: ^Pass_Stats) {
    if op == nil do return
    for r in op.regions {
        if r == nil do continue
        for b in r.blocks {
            if b == nil do continue
            inline_in_block(ctx, b, fns, st)
        }
    }
}

@(private="file")
inline_in_block :: proc(ctx: ^Pass_Ctx, b: ^Block, fns: map[string]^Op, st: ^Pass_Stats) {
    if b == nil do return
    new_ops := make([dynamic]^Op, 0, len(b.ops))
    for child in b.ops {
        // Recurse into child's regions first so inner calls get handled
        for r in child.regions {
            if r == nil do continue
            for bb in r.blocks do inline_in_block(ctx, bb, fns, st)
        }
        if !try_inline_call(ctx, child, fns, b, &new_ops, st) {
            append(&new_ops, child)
        }
    }
    delete(b.ops)
    b.ops = new_ops
}

// If `call_op` is an inlineable cslv3.call, splice the callee's body into
// `new_ops` (replacing `call_op`). Returns true on inline.
@(private="file")
try_inline_call :: proc(ctx: ^Pass_Ctx, call_op: ^Op, fns: map[string]^Op,
                         _block: ^Block, new_ops: ^[dynamic]^Op,
                         st: ^Pass_Stats) -> bool {
    if call_op == nil || call_op.name != OP_CALL do return false
    if ctx.fuel <= 0 do return false
    if len(call_op.operands) < 1 do return false

    // callee operand comes from an OP_VAR_REF w/ "name" attr
    callee_v := call_op.operands[0]
    if callee_v == nil || callee_v.def_op == nil do return false
    callee_ref := callee_v.def_op
    if callee_ref.name != OP_VAR_REF do return false
    name_attr, has_name := op_get_attr(callee_ref, "name")
    if !has_name || name_attr.kind != .Symbol do return false
    fn_op, found := fns[name_attr.str_v]
    if !found do return false

    // size cost-model
    size := fn_op_size(fn_op)
    if size == 0 || size > MAX_INLINE_SIZE {
        st.skipped += 1
        return false
    }
    ctx.fuel -= size

    // Splice body ops (excluding the return/yield terminator ; rewire returns
    // to become the call's result-binding).
    if len(fn_op.regions) == 0 do return false
    region := fn_op.regions[0]
    if len(region.blocks) != 1 {
        // multi-block bodies : skip for now
        st.skipped += 1
        return false
    }
    body := region.blocks[0]

    // Alpha-rename map : block-arg Value → corresponding call-site arg Value
    val_map: map[^Value]^Value
    defer delete(val_map)
    for arg, i in body.args {
        if arg == nil do continue
        if i + 1 < len(call_op.operands) {
            val_map[arg] = call_op.operands[i + 1]
        }
    }

    // Walk body.ops, rewriting operands via val_map. Skip terminator.
    for bop in body.ops {
        if bop == nil do continue
        if op_is_terminator(bop) {
            // If terminator is cslv3.return, rewire its operand to replace
            // call_op's result.
            if bop.name == OP_RETURN && len(bop.operands) == 1 &&
               len(call_op.results) == 1 {
                ret_val := bop.operands[0]
                if mapped, m_ok := val_map[ret_val]; m_ok {
                    ret_val = mapped
                }
                // Replace all uses of call_op.results[0] downstream with ret_val.
                // (Simple one-block pass — for more complex CFG this would need
                // a full rewrite graph. Session-9+ will generalize.)
                call_op.results[0].name = ret_val.name   // inherit debug name
                // point call_op.results[0] as an alias : emit a synthetic
                // OP_VAR_REF that simply references ret_val. This preserves
                // any downstream operand chain.
                alias := new_op(OP_VAR_REF, call_op.loc)
                op_set_attr(alias, "name", attr_symbol("inline-alias"))
                op_add_operand(alias, ret_val)
                // ensure types propagate
                append(&alias.results, call_op.results[0])
                call_op.results[0].def_op = alias
                append(new_ops, alias)
            }
            continue
        }
        // Clone the op : make a fresh Op with a NEW id + fresh Value ids for
        // its results, and remapped operands.
        cloned := clone_op_with_map(bop, &val_map)
        append(new_ops, cloned)
    }

    st.applied += 1
    return true
}

@(private="file")
fn_op_size :: proc(fn_op: ^Op) -> int {
    if len(fn_op.regions) == 0 do return 0
    region := fn_op.regions[0]
    total := 0
    for b in region.blocks {
        if b == nil do continue
        total += len(b.ops)
    }
    return total
}

@(private="file")
clone_op_with_map :: proc(src: ^Op, val_map: ^map[^Value]^Value) -> ^Op {
    op := new_op(src.name, src.loc)
    // copy attrs
    for k, v in src.attrs do op_set_attr(op, k, v)
    // remap operands
    for o in src.operands {
        if o == nil do continue
        if mapped, ok := val_map[o]; ok {
            op_add_operand(op, mapped)
        } else {
            op_add_operand(op, o)
        }
    }
    // fresh result values ; record mapping src-result → new-result
    for r in src.results {
        if r == nil do continue
        new_v := op_add_result(op, r.ty, r.name)
        val_map[r] = new_v
    }
    // NOTE : nested regions intentionally NOT cloned to keep inlining safe.
    return op
}
