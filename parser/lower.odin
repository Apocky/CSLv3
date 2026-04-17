package cslparser

// § CSLv3 AST → IR LOWERING (T21 Session-6)
// I> typed-AST (from T20 infer.odin) → SSA+regions Module
// I> Braun-style on-the-fly SSA — walks AST, builds ops as it descends
// I> error-accumulating : diagnostics collected, emission continues
// I> value-map : AST-Node ptr → ^Value for use-def wiring
// W! every result Value must be attached to exactly one defining Op/Block
// W! every block ends with exactly one terminator op
// W! morpheme-tag + refinement-assert preserved as explicit ops

import "core:fmt"
import "core:strings"

// ---------- Context ----------

Lower_Ctx :: struct {
    module:          ^Module,
    current_block:   ^Block,
    current_fn_op:   ^Op,            // for lowering `return` in nested blocks
    value_map:       map[rawptr]^Value,  // AST-node ptr → SSA value
    env_stack:       [dynamic]map[string]^Value,
    diagnostics:     [dynamic]Sem_Diag,
    tc:              ^Tc_Result,     // from T20 : lookup node-types
    source_file:     string,
}

lower_ctx_init :: proc(ctx: ^Lower_Ctx, tc: ^Tc_Result, source_file: string) {
    ctx.module      = new_module(source_file)
    ctx.value_map   = make(map[rawptr]^Value)
    ctx.env_stack   = make([dynamic]map[string]^Value)
    ctx.diagnostics = make([dynamic]Sem_Diag)
    ctx.tc          = tc
    ctx.source_file = source_file
    env_push(ctx)
}

lower_ctx_destroy :: proc(ctx: ^Lower_Ctx) {
    delete(ctx.value_map)
    for env in ctx.env_stack do delete(env)
    delete(ctx.env_stack)
    delete(ctx.diagnostics)
}

@(private="file")
env_push :: proc(ctx: ^Lower_Ctx) {
    append(&ctx.env_stack, make(map[string]^Value))
}

@(private="file")
env_pop :: proc(ctx: ^Lower_Ctx) {
    if len(ctx.env_stack) == 0 do return
    last := &ctx.env_stack[len(ctx.env_stack) - 1]
    delete(last^)
    pop(&ctx.env_stack)
}

@(private="file")
env_bind :: proc(ctx: ^Lower_Ctx, name: string, v: ^Value) {
    if len(ctx.env_stack) == 0 do return
    top := &ctx.env_stack[len(ctx.env_stack) - 1]
    top^[name] = v
}

@(private="file")
env_lookup :: proc(ctx: ^Lower_Ctx, name: string) -> (v: ^Value, ok: bool) {
    for i := len(ctx.env_stack) - 1; i >= 0; i -= 1 {
        if val, found := ctx.env_stack[i][name]; found do return val, true
    }
    return nil, false
}

@(private="file")
lc_diag :: proc(ctx: ^Lower_Ctx, sev: Sem_Severity, pos: Source_Pos, msg: string) {
    append(&ctx.diagnostics, Sem_Diag{
        code = .Ir_Lower,
        severity = sev,
        pos = pos,
        msg = strings.clone(msg),
    })
}

@(private="file")
node_type :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Type {
    if ctx.tc == nil do return t_var()
    if t, ok := ctx.tc.types[rawptr(n)]; ok do return t
    return t_var()
}

// ---------- Public entry ----------

Lower_Result :: struct {
    module: ^Module,
    diagnostics: [dynamic]Sem_Diag,
}

lower_source :: proc(doc: ^Node, tc: ^Tc_Result, source_file: string) -> Lower_Result {
    ir_reset_ids()
    ctx: Lower_Ctx
    lower_ctx_init(&ctx, tc, source_file)
    defer lower_ctx_destroy(&ctx)

    if doc == nil {
        return Lower_Result{module = ctx.module, diagnostics = ctx.diagnostics}
    }
    lower_document(&ctx, doc)
    return Lower_Result{module = ctx.module, diagnostics = ctx.diagnostics}
}

// ---------- Document / Section ----------

@(private="file")
lower_document :: proc(ctx: ^Lower_Ctx, n: ^Node) {
    if n == nil do return
    #partial switch n.kind {
    case .Document, .Section:
        for c in n.children do lower_document(ctx, c)
    case .Function_Def:
        lower_fn(ctx, n)
    case .Type_Def, .Enum_Def:
        // emit a trivial module-level attr op for now (records metadata)
        op := new_op(OP_VAR_REF, n.pos)
        op_set_attr(op, "name", attr_symbol(n.text))
        op_set_attr(op, "kind", attr_str("type-def"))
        module_append_op(ctx.module, op)
    case .Definition:
        // top-level name : T = expr — emit a `cslv3.fn` wrapper or a const.
        // For non-function bindings at module top-level we emit a const-initializer fn.
        lower_top_def(ctx, n)
    }
}

// ---------- Function ----------

@(private="file")
lower_fn :: proc(ctx: ^Lower_Ctx, n: ^Node) {
    if n == nil do return
    fn_ty := node_type(ctx, n)
    op := new_op(OP_FN, n.pos)
    op_set_attr(op, "name", attr_symbol(n.text))
    op_set_attr(op, "sig", attr_type(fn_ty))
    if n.suffix != .Invalid {
        op_set_attr(op, "morpheme", attr_str(token_kind_name(n.suffix)))
    }
    module_append_op(ctx.module, op)

    region := new_region(op, .Fn_Body)
    op_add_region(op, region)
    entry := new_block("entry", region)
    region_add_block(region, entry)

    // push scope + push fn-op tracker
    save_block := ctx.current_block
    save_fn_op := ctx.current_fn_op
    ctx.current_block = entry
    ctx.current_fn_op = op
    defer { ctx.current_block = save_block ; ctx.current_fn_op = save_fn_op }
    env_push(ctx); defer env_pop(ctx)

    // block-arg per param
    if len(n.children) > 0 && n.children[0] != nil {
        params := n.children[0]
        for p in params.children {
            if p == nil do continue
            p_ty := node_type(ctx, p)
            arg := block_add_arg(entry, p_ty, p.text)
            env_bind(ctx, p.text, arg)
            ctx.value_map[rawptr(p)] = arg
        }
    }

    // body : children[1] if present
    ret_val: ^Value
    if len(n.children) > 1 && n.children[1] != nil {
        ret_val = lower_expr(ctx, n.children[1])
    }
    // synthetic return terminator
    term := new_op(OP_RETURN, n.pos)
    if ret_val != nil do op_add_operand(term, ret_val)
    block_append_op(entry, term)
}

@(private="file")
lower_top_def :: proc(ctx: ^Lower_Ctx, n: ^Node) {
    // Top-level `name : T = expr` — wrap as a zero-arg fn returning expr
    if n == nil || len(n.children) == 0 do return
    subj := n.children[0]
    if subj == nil do return

    name := subj.text
    if len(name) == 0 do name = "_anon"

    op := new_op(OP_FN, n.pos)
    op_set_attr(op, "name", attr_symbol(name))
    op_set_attr(op, "kind", attr_str("top-const"))
    if subj.suffix != .Invalid {
        op_set_attr(op, "morpheme", attr_str(token_kind_name(subj.suffix)))
    }
    module_append_op(ctx.module, op)

    region := new_region(op, .Fn_Body)
    op_add_region(op, region)
    entry := new_block("entry", region)
    region_add_block(region, entry)

    save_block := ctx.current_block
    save_fn_op := ctx.current_fn_op
    ctx.current_block = entry
    ctx.current_fn_op = op
    defer { ctx.current_block = save_block ; ctx.current_fn_op = save_fn_op }
    env_push(ctx); defer env_pop(ctx)

    ret_val: ^Value
    if len(n.children) > 1 && n.children[1] != nil {
        ret_val = lower_expr(ctx, n.children[1])
    }
    // if no rhs : return zero-equivalent (const nil)
    if ret_val == nil {
        c := new_op(OP_CONST, n.pos)
        op_set_attr(c, "value", attr_symbol("nil"))
        ret_val = op_add_result(c, t_unit())
        block_append_op(entry, c)
    }
    term := new_op(OP_RETURN, n.pos)
    op_add_operand(term, ret_val)
    block_append_op(entry, term)
}

// ---------- Statements inside a block ----------

@(private="file")
lower_stmt :: proc(ctx: ^Lower_Ctx, n: ^Node) {
    if n == nil do return
    #partial switch n.kind {
    case .Definition:
        // let-binding : name = expr OR name : T = expr
        if len(n.children) == 0 do return
        subj := n.children[0]
        rhs_val: ^Value
        if len(n.children) > 1 && n.children[1] != nil {
            rhs_val = lower_expr(ctx, n.children[1])
        }
        if subj != nil && rhs_val != nil {
            // morpheme-suffix on subj → wrap with morpheme.tag op
            if subj.suffix != .Invalid {
                morph_op := new_op(OP_MORPH, subj.pos)
                op_add_operand(morph_op, rhs_val)
                op_set_attr(morph_op, "morpheme", attr_str(token_kind_name(subj.suffix)))
                tagged_ty := node_type(ctx, subj)
                rhs_val = op_add_result(morph_op, tagged_ty, subj.text)
                block_append_op(ctx.current_block, morph_op)
            }
            env_bind(ctx, subj.text, rhs_val)
            ctx.value_map[rawptr(subj)] = rhs_val
        }
    case .Expr_Stmt:
        for c in n.children do _ = lower_expr(ctx, c)
    case .Relation:
        for c in n.children do _ = lower_expr(ctx, c)
    case .Conditional:
        lower_if(ctx, n)
    case .ForAll_Stmt:
        lower_for(ctx, n)
    case .Block:
        for c in n.children do lower_stmt(ctx, c)
    case .Directive, .Alias_Def, .Import, .Export, .Comment:
        // metadata — no IR emission
    case:
        _ = lower_expr(ctx, n)
    }
}

// ---------- Expressions ----------

@(private="file")
lower_expr :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    if n == nil do return nil
    if v, ok := ctx.value_map[rawptr(n)]; ok do return v

    v := lower_expr_core(ctx, n)
    if v != nil do ctx.value_map[rawptr(n)] = v
    return v
}

@(private="file")
lower_expr_core :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    #partial switch n.kind {
    case .Num_Lit:
        op := new_op(OP_CONST, n.pos)
        if n.is_float do op_set_attr(op, "value", attr_float(n.float_val))
        else           do op_set_attr(op, "value", attr_int(n.int_val))
        ty := node_type(ctx, n)
        r := op_add_result(op, ty)
        block_append_op(ctx.current_block, op)
        return r
    case .Str_Lit:
        op := new_op(OP_CONST, n.pos)
        op_set_attr(op, "value", attr_str(n.text))
        r := op_add_result(op, t_prim(.String))
        block_append_op(ctx.current_block, op)
        return r
    case .Bool_Lit:
        op := new_op(OP_CONST, n.pos)
        op_set_attr(op, "value", attr_bool(n.bool_val))
        r := op_add_result(op, t_prim(.Bool))
        block_append_op(ctx.current_block, op)
        return r
    case .Nil_Lit:
        op := new_op(OP_CONST, n.pos)
        op_set_attr(op, "value", attr_symbol("nil"))
        r := op_add_result(op, t_unit())
        block_append_op(ctx.current_block, op)
        return r
    case .Ident:
        if v, ok := env_lookup(ctx, n.text); ok do return v
        // unresolved : emit var_ref (verifier may downgrade)
        op := new_op(OP_VAR_REF, n.pos)
        op_set_attr(op, "name", attr_symbol(n.text))
        ty := node_type(ctx, n)
        r := op_add_result(op, ty)
        block_append_op(ctx.current_block, op)
        return r
    case .Binary:
        return lower_binary(ctx, n)
    case .Unary:
        return lower_unary(ctx, n)
    case .Call:
        return lower_call(ctx, n)
    case .Compound_Expr:
        return lower_compound(ctx, n)
    case .Conditional:
        return lower_if_expr(ctx, n)
    case .Group:
        if len(n.children) > 0 do return lower_expr(ctx, n.children[0])
        return lower_nil_const(ctx, n.pos)
    case .Tuple_Expr:
        return lower_tuple(ctx, n)
    case .List_Expr:
        return lower_list(ctx, n)
    case .Record_Expr:
        return lower_record(ctx, n)
    case .Match_Stmt:
        return lower_match(ctx, n)
    case .Block:
        return lower_block_expr(ctx, n)
    case .Lambda:
        return lower_lambda(ctx, n)
    case .Type_Prim:
        // Type-literal as value : emit a const carrying the type.
        op := new_op(OP_CONST, n.pos)
        op_set_attr(op, "value", attr_type(node_type(ctx, n)))
        r := op_add_result(op, node_type(ctx, n))
        block_append_op(ctx.current_block, op)
        return r
    }
    // fallback : emit unresolved var_ref
    op := new_op(OP_VAR_REF, n.pos)
    op_set_attr(op, "name", attr_symbol(n.text))
    r := op_add_result(op, node_type(ctx, n))
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
lower_nil_const :: proc(ctx: ^Lower_Ctx, pos: Source_Pos) -> ^Value {
    op := new_op(OP_CONST, pos)
    op_set_attr(op, "value", attr_symbol("nil"))
    r := op_add_result(op, t_unit())
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
lower_binary :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    if len(n.children) < 2 do return lower_nil_const(ctx, n.pos)
    lhs := lower_expr(ctx, n.children[0])
    rhs := lower_expr(ctx, n.children[1])
    name: string = binop_ir_name(n.op)
    op := new_op(name, n.pos)
    op_add_operand(op, lhs)
    op_add_operand(op, rhs)
    result_ty := ir_binop_result_ty(name, lhs != nil ? lhs.ty : t_var(), rhs != nil ? rhs.ty : t_var())
    r := op_add_result(op, result_ty)
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
binop_ir_name :: proc(k: Token_Kind) -> string {
    #partial switch k {
    case .Plus:    return OP_ADD
    case .Minus:   return OP_SUB
    case .Star:    return OP_MUL
    case .Slash:   return OP_DIV
    case .Percent: return OP_MOD
    case .EqEq:    return OP_EQ
    case .NotEq:   return OP_NEQ
    case .Lt:      return OP_LT
    case .Lte:     return OP_LE
    case .Gt:      return OP_GT
    case .Gte:     return OP_GE
    case .And:     return OP_AND
    case .Or:      return OP_OR
    case .Eq:      return OP_EQ  // treat `=` as equality at expression level
    case .Identical: return OP_EQ
    case .Arrow_Right, .Implies, .Causes, .PipeFwd:
        // flow ops — encoded as calls where RHS is callee (future) ; treat as pair for now
        return OP_CALL
    }
    return OP_CALL   // default : fold under generic call (safe fallback)
}

@(private="file")
lower_unary :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    if len(n.children) == 0 do return lower_nil_const(ctx, n.pos)
    inner := lower_expr(ctx, n.children[0])
    name: string
    #partial switch n.op {
    case .Not, .Tilde, .Bang:   name = OP_NOT
    case .Minus:                name = OP_SUB    // unary minus
    case:                       name = OP_NOT
    }
    op := new_op(name, n.pos)
    op_add_operand(op, inner)
    r := op_add_result(op, inner != nil ? inner.ty : t_var())
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
lower_call :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    op := new_op(OP_CALL, n.pos)
    if len(n.children) > 0 {
        callee_val := lower_expr(ctx, n.children[0])
        op_add_operand(op, callee_val)
    }
    for i in 1 ..< len(n.children) {
        op_add_operand(op, lower_expr(ctx, n.children[i]))
    }
    r := op_add_result(op, node_type(ctx, n))
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
lower_compound :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    if len(n.children) < 2 do return lower_nil_const(ctx, n.pos)
    lhs := lower_expr(ctx, n.children[0])
    rhs_label := n.children[1].text if n.children[1].kind == .Ident else ""
    name: string = compound_ir_name(n.op)
    op := new_op(name, n.pos)
    if lhs != nil do op_add_operand(op, lhs)
    if len(rhs_label) > 0 do op_set_attr(op, "label", attr_label(rhs_label))
    // morpheme chain on result
    for m in n.morphemes {
        op_set_attr(op, fmt.tprintf("morph_%s", m), attr_bool(true))
    }
    r := op_add_result(op, node_type(ctx, n))
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
compound_ir_name :: proc(k: Token_Kind) -> string {
    #partial switch k {
    case .Dot:    return OP_COMP_OF
    case .Plus:   return OP_COMP_AND
    case .Minus:  return OP_COMP_THAT_IS
    case .Tensor: return OP_COMP_HAVING
    case .At:     return OP_COMP_AT
    }
    return OP_COMP_OF
}

@(private="file")
lower_if_expr :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    if len(n.children) == 0 do return lower_nil_const(ctx, n.pos)
    cond := lower_expr(ctx, n.children[0])
    op := new_op(OP_IF, n.pos)
    if cond != nil do op_add_operand(op, cond)

    then_region := new_region(op, .If_Then)
    else_region := new_region(op, .If_Else)
    op_add_region(op, then_region)
    op_add_region(op, else_region)

    result_ty := node_type(ctx, n)

    // THEN region
    then_block := new_block("then", then_region)
    region_add_block(then_region, then_block)
    save1 := ctx.current_block
    ctx.current_block = then_block
    then_val: ^Value
    if len(n.children) > 1 do then_val = lower_expr(ctx, n.children[1])
    term_then := new_op("cslv3.yield", n.pos)
    if then_val != nil do op_add_operand(term_then, then_val)
    block_append_op(then_block, term_then)
    ctx.current_block = save1

    // ELSE region
    else_block := new_block("else", else_region)
    region_add_block(else_region, else_block)
    save2 := ctx.current_block
    ctx.current_block = else_block
    else_val: ^Value
    if len(n.children) > 2 do else_val = lower_expr(ctx, n.children[2])
    term_else := new_op("cslv3.yield", n.pos)
    if else_val != nil do op_add_operand(term_else, else_val)
    block_append_op(else_block, term_else)
    ctx.current_block = save2

    // op result : resolves to whichever yield fires
    r := op_add_result(op, result_ty)
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
lower_if :: proc(ctx: ^Lower_Ctx, n: ^Node) {
    _ = lower_if_expr(ctx, n)
}

@(private="file")
lower_for :: proc(ctx: ^Lower_Ctx, n: ^Node) {
    op := new_op(OP_FOR, n.pos)
    op_set_attr(op, "var", attr_str(n.text))
    if len(n.children) > 0 {
        iter_v := lower_expr(ctx, n.children[0])
        if iter_v != nil do op_add_operand(op, iter_v)
    }
    body_region := new_region(op, .For_Body)
    op_add_region(op, body_region)
    body_block := new_block("body", body_region)
    region_add_block(body_region, body_block)

    save := ctx.current_block
    ctx.current_block = body_block
    env_push(ctx); defer env_pop(ctx)
    if len(n.children) > 1 && n.children[1] != nil {
        b := n.children[1]
        #partial switch b.kind {
        case .Block:
            for c in b.children do lower_stmt(ctx, c)
        case:
            lower_stmt(ctx, b)
        }
    }
    term := new_op("cslv3.yield", n.pos)
    block_append_op(body_block, term)
    ctx.current_block = save

    block_append_op(ctx.current_block, op)
}

@(private="file")
lower_tuple :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    op := new_op(OP_RECORD, n.pos)
    op_set_attr(op, "shape", attr_str("tuple"))
    for c in n.children {
        if c != nil do op_add_operand(op, lower_expr(ctx, c))
    }
    r := op_add_result(op, node_type(ctx, n))
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
lower_list :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    op := new_op(OP_RECORD, n.pos)
    op_set_attr(op, "shape", attr_str("list"))
    for c in n.children {
        if c != nil do op_add_operand(op, lower_expr(ctx, c))
    }
    r := op_add_result(op, node_type(ctx, n))
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
lower_record :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    op := new_op(OP_RECORD, n.pos)
    op_set_attr(op, "shape", attr_str("record"))
    for c in n.children {
        if c != nil do op_add_operand(op, lower_expr(ctx, c))
    }
    r := op_add_result(op, node_type(ctx, n))
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
lower_match :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    op := new_op(OP_MATCH, n.pos)
    if len(n.children) > 0 {
        scrut := lower_expr(ctx, n.children[0])
        if scrut != nil do op_add_operand(op, scrut)
    }
    // arms as regions
    for i in 1 ..< len(n.children) {
        arm := n.children[i]
        if arm == nil do continue
        arm_region := new_region(op, .Match_Arm)
        op_add_region(op, arm_region)
        arm_block := new_block(fmt.tprintf("arm%d", i), arm_region)
        region_add_block(arm_region, arm_block)
        save := ctx.current_block
        ctx.current_block = arm_block
        env_push(ctx)
        // arm.children : [pattern, body]
        body_val: ^Value
        if len(arm.children) >= 2 do body_val = lower_expr(ctx, arm.children[1])
        term := new_op("cslv3.yield", arm.pos)
        if body_val != nil do op_add_operand(term, body_val)
        block_append_op(arm_block, term)
        env_pop(ctx)
        ctx.current_block = save
    }
    r := op_add_result(op, node_type(ctx, n))
    block_append_op(ctx.current_block, op)
    return r
}

@(private="file")
lower_block_expr :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    env_push(ctx); defer env_pop(ctx)
    last: ^Value
    for c in n.children {
        if c == nil do continue
        #partial switch c.kind {
        case .Definition:
            lower_stmt(ctx, c)
            last = nil
        case:
            last = lower_expr(ctx, c)
        }
    }
    if last != nil do return last
    return lower_nil_const(ctx, n.pos)
}

@(private="file")
lower_lambda :: proc(ctx: ^Lower_Ctx, n: ^Node) -> ^Value {
    // emit a nested cslv3.fn as an expression (module-level).
    // result is a value of fn-type ; lowered body follows same lower_fn pattern.
    op := new_op(OP_FN, n.pos)
    op_set_attr(op, "name", attr_symbol("_lambda"))
    op_set_attr(op, "kind", attr_str("lambda"))
    fn_ty := node_type(ctx, n)
    op_set_attr(op, "sig", attr_type(fn_ty))

    region := new_region(op, .Fn_Body)
    op_add_region(op, region)
    entry := new_block("entry", region)
    region_add_block(region, entry)

    save_block := ctx.current_block
    save_fn := ctx.current_fn_op
    ctx.current_block = entry
    ctx.current_fn_op = op
    defer { ctx.current_block = save_block ; ctx.current_fn_op = save_fn }
    env_push(ctx); defer env_pop(ctx)

    n_params := len(n.children) - 1
    if n_params < 0 do n_params = 0
    for i in 0 ..< n_params {
        p := n.children[i]
        if p == nil do continue
        pty := node_type(ctx, p)
        arg := block_add_arg(entry, pty, p.text)
        env_bind(ctx, p.text, arg)
    }
    ret_val: ^Value
    if len(n.children) > 0 do ret_val = lower_expr(ctx, n.children[len(n.children) - 1])
    term := new_op(OP_RETURN, n.pos)
    if ret_val != nil do op_add_operand(term, ret_val)
    block_append_op(entry, term)

    // result value of the lambda-op : the fn-value itself.
    r := op_add_result(op, fn_ty, "_lambda")
    // append the lambda-op to the current block as an expression-producing op.
    block_append_op(save_block, op)
    _ = save_block
    return r
}
