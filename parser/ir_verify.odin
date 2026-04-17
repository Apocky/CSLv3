package cslparser

// § CSLv3 IR VERIFIER (T21.c Session-6)
// I> structural invariants over a lowered Module — accumulating, never fail-fast
// I> five classes of check :
//    V1 region-shape         ← op-name → expected Region_Kind[]
//    V2 terminator-shape     ← every non-empty block ends w/ a terminator
//    V3 terminator-kind      ← terminator appropriate for its containing Region_Kind
//    V4 type-consistency     ← per-op-signature (binops same-ty, return-ty matches fn-sig, …)
//    V5 use-before-def       ← DFS walk ; each operand defined earlier in structural-order
// I> no-dangling-values also fused into V5 (any operand with nil def_op AND nil def_block = dangling)
// R! ← MLIR-verifier pattern (per-op traits-based but simplified for our closed op-set)

import "core:fmt"
import "core:strings"

// ---------- Result ----------

Ir_Verify_Result :: struct {
    diagnostics: [dynamic]Sem_Diag,
    errors:      int,
    warnings:    int,
}

ir_verify_result_destroy :: proc(r: ^Ir_Verify_Result) {
    delete(r.diagnostics)
}

// ---------- State ----------

@(private="file")
Verify_Ctx :: struct {
    diagnostics: [dynamic]Sem_Diag,
    // set of Values that have been defined so far in structural-DFS order
    defined:     map[^Value]bool,
    // current enclosing fn-op (for return-type check)
    current_fn:  ^Op,
}

@(private="file")
vctx_init :: proc(ctx: ^Verify_Ctx) {
    ctx.diagnostics = make([dynamic]Sem_Diag)
    ctx.defined     = make(map[^Value]bool)
}

@(private="file")
vctx_destroy :: proc(ctx: ^Verify_Ctx) {
    delete(ctx.defined)
    // diagnostics are moved out to result — do NOT delete here
}

@(private="file")
vdiag :: proc(ctx: ^Verify_Ctx, code: Sem_Code, pos: Source_Pos, msg: string) {
    sev := severity_for(code, .Default, false)
    append(&ctx.diagnostics, Sem_Diag{
        code     = code,
        severity = sev,
        pos      = pos,
        msg      = strings.clone(msg),
    })
}

// ---------- Public entry ----------

ir_verify :: proc(m: ^Module) -> Ir_Verify_Result {
    ctx: Verify_Ctx
    vctx_init(&ctx)
    defer vctx_destroy(&ctx)

    if m == nil {
        return Ir_Verify_Result{diagnostics = ctx.diagnostics}
    }

    for op in m.ops {
        verify_top_op(&ctx, op)
    }

    r := Ir_Verify_Result{diagnostics = ctx.diagnostics}
    for d in r.diagnostics {
        switch d.severity {
        case .Error: r.errors   += 1
        case .Warn:  r.warnings += 1
        case .Info:  // nothing
        }
    }
    return r
}

// ---------- Op-dispatch ----------

@(private="file")
verify_top_op :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    if op == nil do return
    // Module-top-level is either fn or metadata op (var_ref w/ kind=type-def attr etc.)
    switch op.name {
    case OP_FN:
        verify_fn_op(ctx, op)
    case:
        // metadata op ; allow zero regions + no operands
        verify_region_count(ctx, op, 0)
    }
}

@(private="file")
verify_fn_op :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    if !verify_region_count(ctx, op, 1) do return
    region := op.regions[0]
    if region.kind != .Fn_Body {
        vdiag(ctx, .Ir_Region_Shape, op.loc,
              fmt.tprintf("cslv3.fn region must be Fn_Body, got %v", region.kind))
    }
    if len(region.blocks) == 0 {
        vdiag(ctx, .Ir_Region_Shape, op.loc, "cslv3.fn region has no entry block")
        return
    }

    save_fn := ctx.current_fn
    ctx.current_fn = op
    defer ctx.current_fn = save_fn

    // Each block's block-args are defined at block-entry.
    // Walk blocks in declared order (structured-CFG ⇒ this is a topo-order).
    for b in region.blocks {
        verify_block(ctx, b)
    }
}

// ---------- Region-count checks ----------

@(private="file")
verify_region_count :: proc(ctx: ^Verify_Ctx, op: ^Op, want: int) -> bool {
    if len(op.regions) != want {
        vdiag(ctx, .Ir_Region_Shape, op.loc,
              fmt.tprintf("%s: expected %d region(s), got %d", op.name, want, len(op.regions)))
        return false
    }
    return true
}

@(private="file")
verify_region_kinds :: proc(ctx: ^Verify_Ctx, op: ^Op, kinds: []Region_Kind) -> bool {
    if !verify_region_count(ctx, op, len(kinds)) do return false
    ok := true
    for i in 0..<len(kinds) {
        if op.regions[i].kind != kinds[i] {
            vdiag(ctx, .Ir_Region_Shape, op.loc,
                  fmt.tprintf("%s: region[%d] expected %v, got %v",
                              op.name, i, kinds[i], op.regions[i].kind))
            ok = false
        }
    }
    return ok
}

// ---------- Block walker ----------

@(private="file")
verify_block :: proc(ctx: ^Verify_Ctx, b: ^Block) {
    if b == nil do return

    // Declare block-args as defined
    for a in b.args {
        ctx.defined[a] = true
        verify_value_wellformed(ctx, a, b.ops[0].loc if len(b.ops) > 0 else Source_Pos{})
    }

    // Walk ops in order
    for op in b.ops {
        verify_op_operands(ctx, op)
        verify_op_signature(ctx, op)
        // recurse into sub-regions BEFORE declaring this op's results,
        // so that inner ops cannot reference outer-op's results that
        // haven't been defined yet in the dominance order.
        for r in op.regions {
            verify_region_body(ctx, r)
        }
        // declare results of this op after its body is verified
        for v in op.results {
            ctx.defined[v] = true
        }
    }

    // Terminator presence + kind
    verify_block_terminator(ctx, b)
}

@(private="file")
verify_region_body :: proc(ctx: ^Verify_Ctx, r: ^Region) {
    if r == nil do return
    // The parent op dispatches shape-check ; we only walk blocks here.
    // Each block's block-args and ops are validated by verify_block.
    for b in r.blocks {
        verify_block(ctx, b)
    }
}

// ---------- Terminator checks ----------

@(private="file")
verify_block_terminator :: proc(ctx: ^Verify_Ctx, b: ^Block) {
    if len(b.ops) == 0 {
        // empty blocks are flagged as missing terminator
        pos := Source_Pos{}
        vdiag(ctx, .Ir_Missing_Terminator, pos,
              fmt.tprintf("block ^%s is empty (needs terminator)", b.label))
        return
    }
    last := b.ops[len(b.ops) - 1]
    if !op_is_terminator(last) {
        vdiag(ctx, .Ir_Missing_Terminator, last.loc,
              fmt.tprintf("block ^%s last op %s is not a terminator", b.label, last.name))
        return
    }

    // No non-terminator may appear after a terminator.
    // (redundant since we only check last ; but catch misordered lowering.)
    for i := 0; i < len(b.ops) - 1; i += 1 {
        if op_is_terminator(b.ops[i]) {
            vdiag(ctx, .Ir_Missing_Terminator, b.ops[i].loc,
                  fmt.tprintf("block ^%s has terminator %s before end (pos=%d/%d)",
                              b.label, b.ops[i].name, i, len(b.ops) - 1))
        }
    }

    // Terminator-kind vs region-kind
    verify_terminator_kind(ctx, b, last)
}

@(private="file")
verify_terminator_kind :: proc(ctx: ^Verify_Ctx, b: ^Block, term: ^Op) {
    if b.parent == nil do return
    rk := b.parent.kind
    tn := term.name

    // Allowed terminators by region kind
    ok := false
    switch rk {
    case .Fn_Body:
        ok = tn == OP_RETURN || tn == "cslv3.branch" || tn == "cslv3.cond_branch"
    case .If_Then, .If_Else, .While_Body, .For_Body, .Match_Arm, .Match_Default, .Handler_Body:
        // structured regions — yield / break / continue acceptable
        ok = tn == "cslv3.yield" || tn == OP_BREAK || tn == OP_CONT || tn == OP_RETURN
    case .While_Cond:
        ok = tn == "cslv3.cond_branch" || tn == "cslv3.yield"
    case .Generic:
        ok = true   // permissive
    }
    if !ok {
        vdiag(ctx, .Ir_Terminator_Kind, term.loc,
              fmt.tprintf("block ^%s in %v region cannot end with %s", b.label, rk, tn))
    }
}

// ---------- Operand-dominance / use-before-def ----------

@(private="file")
verify_op_operands :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    for operand in op.operands {
        if operand == nil {
            vdiag(ctx, .Ir_Dangling_Value, op.loc,
                  fmt.tprintf("%s: nil operand", op.name))
            continue
        }
        // Dangling : neither def_op nor def_block set
        if operand.def_kind == .From_Op && operand.def_op == nil {
            vdiag(ctx, .Ir_Dangling_Value, op.loc,
                  fmt.tprintf("%s: operand %%%d From_Op has nil def_op", op.name, operand.id))
            continue
        }
        if operand.def_kind == .From_Block_Arg && operand.def_block == nil {
            vdiag(ctx, .Ir_Dangling_Value, op.loc,
                  fmt.tprintf("%s: operand %%%d From_Block_Arg has nil def_block", op.name, operand.id))
            continue
        }
        // use-before-def : operand not yet in `defined` set
        if _, ok := ctx.defined[operand]; !ok {
            vdiag(ctx, .Ir_Use_Before_Def, op.loc,
                  fmt.tprintf("%s: operand %%%d used before definition", op.name, operand.id))
        }
    }
}

@(private="file")
verify_value_wellformed :: proc(ctx: ^Verify_Ctx, v: ^Value, pos: Source_Pos) {
    if v == nil do return
    if v.def_kind == .From_Op && v.def_op == nil {
        vdiag(ctx, .Ir_Dangling_Value, pos,
              fmt.tprintf("value %%%d From_Op has nil def_op", v.id))
    }
    if v.def_kind == .From_Block_Arg && v.def_block == nil {
        vdiag(ctx, .Ir_Dangling_Value, pos,
              fmt.tprintf("value %%%d From_Block_Arg has nil def_block", v.id))
    }
}

// ---------- Type-consistency per op-signature ----------

@(private="file")
verify_op_signature :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    switch op.name {
    case OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD:
        verify_binop_arith(ctx, op)
    case OP_EQ, OP_NEQ, OP_LT, OP_LE, OP_GT, OP_GE:
        verify_binop_compare(ctx, op)
    case OP_AND, OP_OR:
        verify_binop_bool(ctx, op)
    case OP_NOT:
        verify_unop_not(ctx, op)
    case OP_CONST:
        verify_const(ctx, op)
    case OP_RETURN:
        verify_return(ctx, op)
    case OP_IF:
        verify_if(ctx, op)
    case OP_WHILE:
        verify_while(ctx, op)
    case OP_FOR:
        verify_for(ctx, op)
    case OP_MATCH:
        verify_match(ctx, op)
    case OP_MORPH:
        verify_morph(ctx, op)
    case OP_REFINE:
        verify_refine(ctx, op)
    case OP_CALL:
        verify_call(ctx, op)
    }
}

@(private="file")
verify_binop_arith :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    verify_arity(ctx, op, 2, 1)
    if len(op.operands) != 2 do return
    lhs, rhs := op.operands[0], op.operands[1]
    if lhs == nil || rhs == nil do return
    if !types_compat(lhs.ty, rhs.ty) {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc,
              fmt.tprintf("%s: lhs %s ≠ rhs %s", op.name, type_repr(lhs.ty), type_repr(rhs.ty)))
    }
    // result must match operand type
    if len(op.results) == 1 && op.results[0] != nil {
        if !types_compat(op.results[0].ty, lhs.ty) {
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("%s: result %s ≠ operand %s",
                              op.name, type_repr(op.results[0].ty), type_repr(lhs.ty)))
        }
    }
    // reject obviously-invalid arith on Bool/String/Symbol
    if t := follow(lhs.ty); t != nil && t.kind == .Prim {
        #partial switch t.prim {
        case .Bool, .String, .Symbol, .Unit:
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("%s: arithmetic on %s not permitted", op.name, prim_name(t.prim)))
        }
    }
}

@(private="file")
verify_binop_compare :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    verify_arity(ctx, op, 2, 1)
    if len(op.operands) != 2 do return
    lhs, rhs := op.operands[0], op.operands[1]
    if lhs == nil || rhs == nil do return
    if !types_compat(lhs.ty, rhs.ty) {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc,
              fmt.tprintf("%s: comparing %s with %s",
                          op.name, type_repr(lhs.ty), type_repr(rhs.ty)))
    }
    if len(op.results) == 1 && op.results[0] != nil {
        if !ty_is_prim(op.results[0].ty, .Bool) {
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("%s: result must be bool, got %s",
                              op.name, type_repr(op.results[0].ty)))
        }
    }
}

@(private="file")
verify_binop_bool :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    verify_arity(ctx, op, 2, 1)
    for operand, i in op.operands {
        if operand == nil do continue
        if !ty_is_prim(operand.ty, .Bool) {
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("%s: operand %d must be bool, got %s",
                              op.name, i, type_repr(operand.ty)))
        }
    }
    if len(op.results) == 1 && op.results[0] != nil && !ty_is_prim(op.results[0].ty, .Bool) {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc,
              fmt.tprintf("%s: result must be bool, got %s",
                          op.name, type_repr(op.results[0].ty)))
    }
}

@(private="file")
verify_unop_not :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    verify_arity(ctx, op, 1, 1)
    if len(op.operands) == 1 && op.operands[0] != nil {
        if !ty_is_prim(op.operands[0].ty, .Bool) {
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("cslv3.not: operand must be bool, got %s",
                              type_repr(op.operands[0].ty)))
        }
    }
}

@(private="file")
verify_const :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    verify_arity(ctx, op, 0, 1)
    if len(op.results) != 1 do return
    v := op.results[0]
    if v == nil || v.ty == nil do return

    a, ok := op_get_attr(op, "value")
    if !ok {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc, "cslv3.const missing 'value' attr")
        return
    }
    t := follow(v.ty)
    if t == nil || t.kind != .Prim do return
    switch a.kind {
    case .Int:
        #partial switch t.prim {
        case .Int, .I8, .I16, .I32, .I64, .U8, .U16, .U32, .U64:
        case:
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("cslv3.const Int attr but result type %s", type_repr(v.ty)))
        }
    case .Float:
        #partial switch t.prim {
        case .Float, .F32, .F64:
        case:
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("cslv3.const Float attr but result type %s", type_repr(v.ty)))
        }
    case .Bool:
        if t.prim != .Bool {
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("cslv3.const Bool attr but result type %s", type_repr(v.ty)))
        }
    case .Str:
        if t.prim != .String {
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("cslv3.const Str attr but result type %s", type_repr(v.ty)))
        }
    case .Symbol:
        // Symbol attr is permitted as Symbol OR Unit result (nil/Unit-typed constants)
        if t.prim != .Symbol && t.prim != .Unit {
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("cslv3.const Symbol attr but result type %s", type_repr(v.ty)))
        }
    case .Type, .Sig, .Label:
        // not value-constants — accept
    }
}

@(private="file")
verify_return :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    // 0 or 1 operand ; 0 results
    if len(op.results) != 0 {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc,
              fmt.tprintf("cslv3.return produces %d result(s), expected 0", len(op.results)))
    }
    if len(op.operands) > 1 {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc,
              fmt.tprintf("cslv3.return has %d operands, expected 0 or 1", len(op.operands)))
    }
    if ctx.current_fn == nil do return
    // Check operand type vs fn's terminal return type (from "sig" attr).
    // Our lowering curries fn(a,b,c)→R into A→B→C→R ; walk .to for each
    // block-arg in the entry block to find R.
    sig_attr, has_sig := op_get_attr(ctx.current_fn, "sig")
    if !has_sig do return
    if sig_attr.kind != .Type || sig_attr.ty_v == nil do return
    fn_ty := follow(sig_attr.ty_v)
    if fn_ty == nil do return
    // count params from entry block of fn
    n_params := 0
    if len(ctx.current_fn.regions) > 0 &&
       len(ctx.current_fn.regions[0].blocks) > 0 {
        n_params = len(ctx.current_fn.regions[0].blocks[0].args)
    }
    want := fn_ty
    for i in 0..<n_params {
        w := follow(want)
        if w == nil || w.kind != .Arrow do break
        want = w.to
    }
    want = follow(want)
    got := t_unit()
    if len(op.operands) == 1 && op.operands[0] != nil {
        got = op.operands[0].ty
    }
    if !types_compat(got, want) {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc,
              fmt.tprintf("cslv3.return type %s does not match fn-return %s",
                          type_repr(got), type_repr(want)))
    }
}

@(private="file")
verify_if :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    // 1 operand (bool condition) ; 0 or 1 result ; 2 regions (then/else)
    verify_region_kinds(ctx, op, []Region_Kind{.If_Then, .If_Else})
    if len(op.operands) < 1 {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc, "cslv3.if: missing condition operand")
    } else if op.operands[0] != nil && !ty_is_prim(op.operands[0].ty, .Bool) {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc,
              fmt.tprintf("cslv3.if: condition must be bool, got %s",
                          type_repr(op.operands[0].ty)))
    }
}

@(private="file")
verify_while :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    verify_region_kinds(ctx, op, []Region_Kind{.While_Cond, .While_Body})
}

@(private="file")
verify_for :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    verify_region_kinds(ctx, op, []Region_Kind{.For_Body})
}

@(private="file")
verify_match :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    if len(op.regions) == 0 {
        vdiag(ctx, .Ir_Region_Shape, op.loc, "cslv3.match: no arms")
        return
    }
    // All regions must be Match_Arm or Match_Default
    for r, i in op.regions {
        if r.kind != .Match_Arm && r.kind != .Match_Default {
            vdiag(ctx, .Ir_Region_Shape, op.loc,
                  fmt.tprintf("cslv3.match region[%d] must be Match_Arm|Match_Default, got %v",
                              i, r.kind))
        }
    }
}

@(private="file")
verify_morph :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    verify_arity(ctx, op, 1, 1)
    if _, ok := op_get_attr(op, "tag"); !ok {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc, "cslv3.morpheme.tag: missing 'tag' attr")
    }
}

@(private="file")
verify_refine :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    verify_arity(ctx, op, 1, 1)
    if _, ok := op_get_attr(op, "pred"); !ok {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc, "cslv3.refinement.assert: missing 'pred' attr")
    }
}

@(private="file")
verify_call :: proc(ctx: ^Verify_Ctx, op: ^Op) {
    if len(op.operands) < 1 {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc, "cslv3.call: missing callee operand")
        return
    }
    callee := op.operands[0]
    if callee == nil || callee.ty == nil do return
    ty := follow(callee.ty)
    if ty == nil || ty.kind != .Arrow do return
    // #args = operand-count - 1 (callee) ; arrow type is curried but we permit
    // uncurried call forms in the IR. Soft check : at least one arg of correct type.
    if ty.from == nil do return
    if len(op.operands) >= 2 {
        first_arg := op.operands[1]
        if first_arg != nil && !types_compat(first_arg.ty, ty.from) {
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("cslv3.call: arg[0] %s ≠ param %s",
                              type_repr(first_arg.ty), type_repr(ty.from)))
        }
    }
    if len(op.results) == 1 && op.results[0] != nil && ty.to != nil {
        if !types_compat(op.results[0].ty, ty.to) {
            vdiag(ctx, .Ir_Type_Mismatch, op.loc,
                  fmt.tprintf("cslv3.call: result %s ≠ return %s",
                              type_repr(op.results[0].ty), type_repr(ty.to)))
        }
    }
}

// ---------- Arity / type helpers ----------

@(private="file")
verify_arity :: proc(ctx: ^Verify_Ctx, op: ^Op, want_ops: int, want_res: int) {
    if len(op.operands) != want_ops {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc,
              fmt.tprintf("%s: expected %d operand(s), got %d",
                          op.name, want_ops, len(op.operands)))
    }
    if len(op.results) != want_res {
        vdiag(ctx, .Ir_Type_Mismatch, op.loc,
              fmt.tprintf("%s: expected %d result(s), got %d",
                          op.name, want_res, len(op.results)))
    }
}

@(private="file")
ty_is_prim :: proc(t: ^Type, p: Prim_Ty) -> bool {
    r := follow(t)
    if r == nil do return false
    return r.kind == .Prim && r.prim == p
}

// Permissive compatibility : Var-Var via same-link-ptr, Var-anything accepted (monomorphic
// lowering may leave tvars ; we don't re-unify here — verifier is read-only).
@(private="file")
types_compat :: proc(a, b: ^Type) -> bool {
    ra := follow(a)
    rb := follow(b)
    if ra == nil || rb == nil do return true   // missing-type : skip, separate check
    if ra == rb do return true
    if ra.kind == .Var || rb.kind == .Var do return true
    if ra.kind != rb.kind do return false
    #partial switch ra.kind {
    case .Prim:
        return ra.prim == rb.prim
    case .Arrow:
        return types_compat(ra.from, rb.from) && types_compat(ra.to, rb.to)
    case .Con:
        return ra.con_name == rb.con_name
    case .Tagged:
        return ra.tag_name == rb.tag_name && types_compat(ra.tag_ty, rb.tag_ty)
    case .Refine:
        return types_compat(ra.base, rb.base)
    case .Tuple:
        if len(ra.con_args) != len(rb.con_args) do return false
        for i in 0..<len(ra.con_args) {
            if !types_compat(ra.con_args[i], rb.con_args[i]) do return false
        }
        return true
    case .Record, .Variant:
        // structural : compare labels pointwise (permissive — no row-tail unify)
        return row_compat(ra.row, rb.row)
    }
    // default : accept for kinds we don't introspect deeper
    return true
}

@(private="file")
row_compat :: proc(a, b: ^Row) -> bool {
    if a == nil || b == nil do return a == b
    if len(a.labels) != len(b.labels) do return false
    for i in 0..<len(a.labels) {
        if a.labels[i].name != b.labels[i].name do return false
        if !types_compat(a.labels[i].ty, b.labels[i].ty) do return false
    }
    return true
}
