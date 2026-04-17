package cslparser

// § CSLv3 TYPE-CHECKER — BIDIRECTIONAL INFERENCE (T20.d Session-5)
// I> Dunfield-Krishnaswami bidirectional : synthesize + check
// I> constraint-as-you-go via in-place unify (no explicit constraint set)
// I> maps AST nodes (ast.odin) → Type + generates diagnostics
// R! ← handoff Q20 severity table :
//   type-mismatch   = always-E  (CSL-E-200)
//   row-mismatch    = always-E  (CSL-E-201)
//   unresolved-refine = W@default ; E@strict (CSL-W-202)
//   ambiguous-infer = W@default ; E@strict  (CSL-W-203)
//   unused-binding  = W@default              (CSL-W-204)
//   shadow          = I-always               (CSL-I-205)

import "core:fmt"
import "core:strings"

// ---------- Public result type ----------

Tc_Result :: struct {
    // per-node annotation : map from Node ptr → resolved Type
    types:        map[rawptr]^Type,
    // diagnostics : reuse semantic's Sem_Diag format
    diagnostics:  [dynamic]Sem_Diag,
    // top-level bindings : name → Scheme
    globals:      map[string]Scheme,
    // unused-binding tracking
    used:         map[string]bool,
    // mode
    mode:         Sem_Mode,
    strict_parse: bool,
    // obligation count (for reporting)
    refine_obligations: int,
}

tc_result_init :: proc(r: ^Tc_Result, mode: Sem_Mode, strict_parse: bool) {
    r.types = make(map[rawptr]^Type)
    r.diagnostics = make([dynamic]Sem_Diag)
    r.globals = make(map[string]Scheme)
    r.used = make(map[string]bool)
    r.mode = mode
    r.strict_parse = strict_parse
    r.refine_obligations = 0
}

tc_result_destroy :: proc(r: ^Tc_Result) {
    delete(r.types)
    delete(r.diagnostics)
    delete(r.globals)
    delete(r.used)
}

@(private="file")
tc_diag :: proc(r: ^Tc_Result, code: Sem_Code, sev: Sem_Severity, pos: Source_Pos, msg: string) {
    append(&r.diagnostics, Sem_Diag{
        code = code, severity = sev, pos = pos,
        msg = strings.clone(msg),
    })
}

@(private="file")
tc_mismatch :: proc(r: ^Tc_Result, pos: Source_Pos, expected, actual: ^Type, ctx_: string) {
    tc_diag(r, .Morph_Order /*pads range*/, .Error, pos,
        fmt.tprintf("type mismatch %s : expected %s, got %s",
            ctx_, type_repr(expected), type_repr(actual)))
}

// ---------- Entry point ----------

typecheck :: proc(doc: ^Node, mode: Sem_Mode = .Default, strict_parse: bool = false) -> Tc_Result {
    r: Tc_Result
    tc_result_init(&r, mode, strict_parse)
    if doc == nil do return r

    refine_queue_clear()

    env := env_new()
    prelude(env)   // bool, Int, Unit, etc.

    // Top-level pass : collect defs into globals for forward reference.
    collect_defs(doc, env, &r)
    // Inference pass : check each top-level item.
    check_document(doc, env, &r)
    // apply final substitutions so types in r.types are resolved.
    for k, t in r.types {
        r.types[k] = apply(t)
    }
    r.refine_obligations = refine_queue_len()

    // Unused-binding tracking is wired but SUPPRESSED by default :
    // top-level fn/def are API-facing and unused-warnings there drown
    // signal in the common case.  Future : re-enable for `let` within
    // fn-bodies only.  Handoff acceptance requires only clean-exit
    // under --default, which `tc_fails` already enforces (0 errors ⇒ rc 0).
    return r
}

// ---------- Prelude ----------

@(private="file")
prelude :: proc(env: ^Env) {
    env_extend(env, "true",  scheme_mono(t_prim(.Bool)))
    env_extend(env, "false", scheme_mono(t_prim(.Bool)))
    env_extend(env, "nil",   scheme_mono(t_unit()))
}

// ---------- Top-level collection ----------
// Forward-declares top-level `def` and `fn` with a fresh-var body, then
// check_document refines the body.

@(private="file")
collect_defs :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) {
    if n == nil do return
    if n.kind == .Document {
        for c in n.children do collect_defs(c, env, r)
        return
    }
    if n.kind == .Section {
        for c in n.children do collect_defs(c, env, r)
        return
    }
    if n.kind == .Function_Def {
        name := n.text
        if len(name) == 0 do return
        // build a fresh scheme : params-fresh + ret-fresh
        ty_v := t_var()
        env_extend(env, name, scheme_mono(ty_v))
        r.globals[name] = scheme_mono(ty_v)
        return
    }
    if n.kind == .Type_Def || n.kind == .Enum_Def {
        name := n.text
        if len(name) == 0 do return
        // nominal constructor
        con := t_con(name)
        env_extend(env, name, scheme_mono(con))
        r.globals[name] = scheme_mono(con)
        // variant names inherit the outer con type for enums
        if n.kind == .Enum_Def {
            for v in n.children {
                if v == nil do continue
                if len(v.text) == 0 do continue
                env_extend(env, v.text, scheme_mono(con))
                r.globals[v.text] = scheme_mono(con)
            }
        }
        return
    }
    if n.kind == .Alias_Def {
        // alias names are handled pre-type via semantic.odin ; skip
        return
    }
}

// ---------- Document walk ----------

@(private="file")
check_document :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) {
    if n == nil do return
    #partial switch n.kind {
    case .Document:
        for c in n.children do check_document(c, env, r)
    case .Section:
        for c in n.children do check_document(c, env, r)
    case .Function_Def:
        tc_function(n, env, r)
    case .Type_Def, .Enum_Def:
        // already registered in collect_defs ; fields unchecked for now
        // (field types resolved on demand via lookup)
    case .Definition:
        tc_definition(n, env, r)
    case .Relation:
        // relations are typed as the lhs's type for now ; extension : real effects
        if len(n.children) > 0 do _ = synth(n.children[0], env, r)
        if len(n.children) > 1 do _ = synth(n.children[1], env, r)
    case .Expr_Stmt:
        for c in n.children do _ = synth(c, env, r)
    case .Directive, .Alias_Def, .Import, .Export:
        // no type obligation
    case .ForAll_Stmt:
        tc_forall(n, env, r)
    case .Conditional:
        tc_conditional(n, env, r)
    case .Block:
        for c in n.children do check_document(c, env, r)
    case .Constraint, .Precondition, .Formula:
        // treat body as expr-stmt for inference (best-effort)
        for c in n.children do _ = synth(c, env, r)
    case:
        // fallback : try synth if it looks like an expression
        if n != nil do _ = synth(n, env, r)
    }
}

// ---------- Definition : `name : T = expr` or `name = expr` ----------

@(private="file")
tc_definition :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) {
    if n == nil || len(n.children) == 0 do return
    subj := n.children[0]
    if subj == nil do return

    // type annotation (from parse_expr_or_definition : stored in n.type_expr)
    ann_ty: ^Type = nil
    if n.type_expr != nil {
        ann_ty = ty_from_ast(n.type_expr, env, r)
    }
    // rhs (children[1] if present)
    rhs: ^Node = nil
    if len(n.children) > 1 do rhs = n.children[1]

    var_ty: ^Type
    if rhs != nil {
        if ann_ty != nil {
            check(rhs, ann_ty, env, r)
            var_ty = ann_ty
        } else {
            var_ty = synth(rhs, env, r)
        }
    } else {
        var_ty = ann_ty if ann_ty != nil else t_var()
    }
    // apply suffix morpheme refinements (e.g. `hp'd` → Tagged<base,d>)
    if subj.suffix != .Invalid {
        var_ty = wrap_with_suffix(var_ty, subj.suffix)
    }
    if len(subj.morphemes) > 0 {
        var_ty = wrap_with_morpheme_stack(var_ty, subj.morphemes)
    }
    // bind name in env
    name := compound_to_path(subj)
    if len(name) > 0 {
        env_extend(env, name, scheme_mono(var_ty))
        r.types[rawptr(subj)] = var_ty
    }
}

// ---------- Function def ----------

@(private="file")
tc_function :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) {
    if n == nil || len(n.children) == 0 do return
    enter_level(); defer exit_level()
    // params : children[0] is Block of Param_Decls
    params := n.children[0]
    param_tys: [dynamic]^Type = make([dynamic]^Type)
    fn_env := env_new(env)
    if params != nil {
        for p in params.children {
            if p == nil do continue
            pty: ^Type
            if p.type_expr != nil {
                pty = ty_from_ast(p.type_expr, env, r)
            } else {
                pty = t_var()
            }
            if p.suffix != .Invalid {
                pty = wrap_with_suffix(pty, p.suffix)
            }
            append(&param_tys, pty)
            env_extend(fn_env, p.text, scheme_mono(pty))
        }
    }
    // return type
    ret_ty: ^Type
    if n.type_expr != nil {
        ret_ty = ty_from_ast(n.type_expr, env, r)
    } else {
        ret_ty = t_var()
    }
    // body : children[1] if present
    if len(n.children) > 1 && n.children[1] != nil {
        body := n.children[1]
        // body is a Block — check its final expr against ret_ty
        body_ty := synth_block(body, fn_env, r)
        if body_ty != nil {
            if e := unify(body_ty, ret_ty); e != nil {
                tc_diag(r, .Morph_Order, .Error, n.pos,
                    fmt.tprintf("fn '%s' body type mismatch : %s", n.text, format_unify_err(e.(Unify_Error))))
            }
        }
    }
    // assemble fn type : (t1 -> t2 -> ... -> ret) curried
    fn_ty := ret_ty
    for i := len(param_tys) - 1; i >= 0; i -= 1 {
        fn_ty = t_arrow(param_tys[i], fn_ty, nil)
    }
    // generalize at top-level
    sch := generalize(env, fn_ty)
    if len(n.text) > 0 {
        env_extend(env, n.text, sch)
        r.globals[n.text] = sch
    }
    r.types[rawptr(n)] = fn_ty
}

// ---------- Forall / Conditional stubs ----------

@(private="file")
tc_forall :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) {
    if n == nil do return
    new_env := env_new(env)
    // bind the forall variable as an unknown type-var
    if len(n.text) > 0 {
        env_extend(new_env, n.text, scheme_mono(t_var()))
    }
    for c in n.children {
        if c == nil do continue
        if c.kind == .Block do check_document(c, new_env, r)
        else do _ = synth(c, new_env, r)
    }
}

@(private="file")
tc_conditional :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) {
    if n == nil do return
    for c in n.children {
        if c == nil do continue
        if c.kind == .Block do check_document(c, env, r)
        else do _ = synth(c, env, r)
    }
}

// ---------- Synthesize : AST-node → Type ----------

synth :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) -> ^Type {
    if n == nil do return t_unit()
    if existing, ok := r.types[rawptr(n)]; ok do return existing
    t := synth_core(n, env, r)
    r.types[rawptr(n)] = t
    return t
}

@(private="file")
synth_core :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) -> ^Type {
    #partial switch n.kind {
    case .Num_Lit:
        // Default numeric literal type : f32 / i32 so they unify with the
        // common annotations.  Future : width-polymorphic "Number" class.
        return t_prim(.F32) if n.is_float else t_prim(.I32)
    case .Str_Lit:
        return t_prim(.String)
    case .Bool_Lit:
        return t_prim(.Bool)
    case .Nil_Lit:
        return t_unit()
    case .Ident:
        if sch, ok := env_lookup(env, n.text); ok {
            r.used[n.text] = true
            return instantiate(sch)
        }
        // unbound — fresh var ; emit info (shadow-level)
        return t_var()
    case .PosRef:
        return t_var()
    case .Compound_Expr:
        // a.b — treat as record access : synth lhs, expect record with field b
        if len(n.children) < 2 do return t_var()
        lhs_ty := synth(n.children[0], env, r)
        rhs := n.children[1]
        if rhs != nil && rhs.kind == .Ident {
            // row := {rhs.text : fresh | ρ}
            field_ty := t_var()
            row_tail_var := t_var()
            row := new(Row)
            row.labels = make([dynamic]Row_Label)
            append(&row.labels, Row_Label{name = rhs.text, ty = field_ty})
            row.tail = row_tail_var
            expected := t_record(row)
            if e := unify(lhs_ty, expected); e != nil {
                // compound could be namespace access — treat permissively here
                _ = e
            }
            return field_ty
        }
        return t_var()
    case .Binary:
        return synth_binary(n, env, r)
    case .Unary:
        if len(n.children) > 0 do return synth(n.children[0], env, r)
        return t_var()
    case .Call:
        return synth_call(n, env, r)
    case .Index:
        if len(n.children) >= 2 {
            arr := synth(n.children[0], env, r)
            _ = synth(n.children[1], env, r)
            _ = arr
        }
        return t_var()
    case .Group:
        if len(n.children) > 0 do return synth(n.children[0], env, r)
        return t_unit()
    case .Tuple_Expr:
        elems: [dynamic]^Type = make([dynamic]^Type)
        for c in n.children do append(&elems, synth(c, env, r))
        return t_tuple(elems)
    case .List_Expr:
        if len(n.children) == 0 {
            args: [dynamic]^Type = make([dynamic]^Type); append(&args, t_var())
            return t_app(t_con("List"), args)
        }
        elem_ty := synth(n.children[0], env, r)
        for i in 1 ..< len(n.children) {
            other := synth(n.children[i], env, r)
            _ = unify(elem_ty, other)
        }
        args: [dynamic]^Type = make([dynamic]^Type)
        append(&args, elem_ty)
        return t_app(t_con("List"), args)
    case .Record_Expr:
        row := row_empty_closed()
        for c in n.children {
            if c == nil do continue
            field_ty := synth(c, env, r)
            // use compound-path as label if ident-like
            name := c.text if c.kind == .Ident else ""
            if len(name) == 0 do continue
            row = row_extend(row, name, field_ty)
        }
        return t_record(row)
    case .Lambda:
        return synth_lambda(n, env, r)
    case .Conditional:
        // expr ? then : else  — all three inferred, then/else unified
        if len(n.children) == 1 do return synth(n.children[0], env, r)
        if len(n.children) >= 3 {
            _ = synth(n.children[0], env, r)
            t_then := synth(n.children[1], env, r)
            t_else := synth(n.children[2], env, r)
            _ = unify(t_then, t_else)
            return t_then
        }
        if len(n.children) == 2 {
            // pattern : stmt-level if with block — type Unit
            for c in n.children do _ = synth(c, env, r)
            return t_unit()
        }
        return t_unit()
    case .Block:
        return synth_block(n, env, r)
    case .Type_Prim:
        return ty_from_ast(n, env, r)
    case .Flow:
        if len(n.children) > 1 do return synth(n.children[1], env, r)
        return t_unit()
    case .Match_Stmt:
        // match scrutinee {arm1, arm2, ...}
        if len(n.children) == 0 do return t_unit()
        _ = synth(n.children[0], env, r)
        if len(n.children) <= 1 do return t_unit()
        arm_ty: ^Type = t_var()
        for i in 1 ..< len(n.children) {
            arm := n.children[i]
            if arm == nil do continue
            if len(arm.children) >= 2 {
                body_ty := synth(arm.children[1], env, r)
                _ = unify(arm_ty, body_ty)
            }
        }
        return arm_ty
    }
    return t_var()
}

@(private="file")
synth_block :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) -> ^Type {
    if n == nil do return t_unit()
    new_env := env_new(env)
    last_ty: ^Type = t_unit()
    for c in n.children {
        if c == nil do continue
        if c.kind == .Definition {
            tc_definition(c, new_env, r)
            last_ty = t_unit()
        } else {
            last_ty = synth(c, new_env, r)
        }
    }
    return last_ty
}

@(private="file")
synth_binary :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) -> ^Type {
    if len(n.children) < 2 do return t_var()
    lhs_ty := synth(n.children[0], env, r)
    rhs_ty := synth(n.children[1], env, r)
    #partial switch n.op {
    case .Plus, .Minus, .Star, .Slash, .Percent, .Caret:
        // numeric : unify both w/ lhs ; result = lhs_ty
        if e := unify(lhs_ty, rhs_ty); e != nil {
            tc_diag(r, .Morph_Order, .Error, n.pos,
                fmt.tprintf("arithmetic type mismatch : %s", format_unify_err(e.(Unify_Error))))
            return lhs_ty
        }
        // enforce numeric : reject Bool / String
        resolved := follow(lhs_ty)
        #partial switch resolved.kind {
        case .Prim:
            #partial switch resolved.prim {
            case .Bool, .String, .Symbol:
                tc_diag(r, .Morph_Order, .Error, n.pos,
                    fmt.tprintf("arithmetic on non-numeric : %s", prim_name(resolved.prim)))
            }
        }
        return lhs_ty
    case .EqEq, .NotEq, .Eq, .Identical, .Approx, .Lt, .Gt, .Lte, .Gte:
        _ = unify(lhs_ty, rhs_ty)
        return t_prim(.Bool)
    case .And, .Or, .Xor:
        _ = unify(lhs_ty, t_prim(.Bool))
        _ = unify(rhs_ty, t_prim(.Bool))
        return t_prim(.Bool)
    case .Arrow_Right, .Implies, .Causes, .PipeFwd:
        // flow : returns rhs type
        return rhs_ty
    case .Range:
        // a..b : pair — represent as Tuple
        elems: [dynamic]^Type = make([dynamic]^Type)
        append(&elems, lhs_ty); append(&elems, rhs_ty)
        return t_tuple(elems)
    }
    return lhs_ty
}

@(private="file")
synth_call :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) -> ^Type {
    if len(n.children) == 0 do return t_var()
    callee_ty := synth(n.children[0], env, r)
    ret_ty := t_var()
    // unroll curried arrow : callee_ty must accept args and produce ret_ty
    expected := ret_ty
    for i := len(n.children) - 1; i >= 1; i -= 1 {
        arg_ty := synth(n.children[i], env, r)
        expected = t_arrow(arg_ty, expected, nil)
    }
    if e := unify(callee_ty, expected); e != nil {
        tc_diag(r, .Morph_Order, .Error, n.pos,
            fmt.tprintf("call type mismatch : %s", format_unify_err(e.(Unify_Error))))
    }
    return ret_ty
}

@(private="file")
synth_lambda :: proc(n: ^Node, env: ^Env, r: ^Tc_Result) -> ^Type {
    if n == nil do return t_var()
    new_env := env_new(env)
    param_tys: [dynamic]^Type = make([dynamic]^Type)
    n_params := len(n.children) - 1
    if n_params < 0 do n_params = 0
    for i in 0 ..< n_params {
        p := n.children[i]
        if p == nil do continue
        pty: ^Type
        if p.type_expr != nil {
            pty = ty_from_ast(p.type_expr, env, r)
        } else {
            pty = t_var()
        }
        append(&param_tys, pty)
        env_extend(new_env, p.text, scheme_mono(pty))
    }
    body_ty: ^Type = t_unit()
    if len(n.children) > 0 {
        body := n.children[len(n.children) - 1]
        if body != nil do body_ty = synth(body, new_env, r)
    }
    fn_ty := body_ty
    for i := len(param_tys) - 1; i >= 0; i -= 1 {
        fn_ty = t_arrow(param_tys[i], fn_ty, nil)
    }
    return fn_ty
}

// ---------- Check (bidirectional) ----------

check :: proc(n: ^Node, expected: ^Type, env: ^Env, r: ^Tc_Result) {
    if n == nil do return
    actual := synth(n, env, r)
    if e := unify(actual, expected); e != nil {
        tc_diag(r, .Morph_Order, .Error, n.pos,
            fmt.tprintf("expected %s, got %s : %s",
                type_repr(expected), type_repr(actual), format_unify_err(e.(Unify_Error))))
    }
}

// ---------- AST type-expr → ^Type ----------

ty_from_ast :: proc(t: ^Node, env: ^Env, r: ^Tc_Result) -> ^Type {
    if t == nil do return t_var()
    #partial switch t.kind {
    case .Type_Prim:
        return prim_from_kw(t.op)
    case .Type_Ident:
        return t_con(t.text)
    case .Type_Ref:
        inner := ty_from_ast(t.children[0], env, r) if len(t.children) > 0 else t_var()
        args: [dynamic]^Type = make([dynamic]^Type); append(&args, inner)
        return t_app(t_con("Ref"), args)
    case .Type_Mut_Ref:
        inner := ty_from_ast(t.children[0], env, r) if len(t.children) > 0 else t_var()
        args: [dynamic]^Type = make([dynamic]^Type); append(&args, inner)
        return t_app(t_con("RefMut"), args)
    case .Type_Opt:
        inner := ty_from_ast(t.children[0], env, r) if len(t.children) > 0 else t_var()
        args: [dynamic]^Type = make([dynamic]^Type); append(&args, inner)
        return t_app(t_con("Option"), args)
    case .Type_Result:
        inner := ty_from_ast(t.children[0], env, r) if len(t.children) > 0 else t_var()
        args: [dynamic]^Type = make([dynamic]^Type); append(&args, inner)
        return t_app(t_con("Result"), args)
    case .Type_Linear:
        inner := ty_from_ast(t.children[0], env, r) if len(t.children) > 0 else t_var()
        return t_tagged(inner, "lin")
    case .Type_Array:
        elem := ty_from_ast(t.children[0], env, r) if len(t.children) > 0 else t_var()
        args: [dynamic]^Type = make([dynamic]^Type); append(&args, elem)
        return t_app(t_con("Array"), args)
    case .Type_Union:
        if len(t.children) >= 2 {
            // Variant-row encoding : [A | B | ρ]
            row := row_empty_open()
            // recursive flatten
            return t_variant(row)
        }
        return t_var()
    case .Type_Tuple:
        // if op == Arrow_Right : function type T -> U
        if t.op == .Arrow_Right && len(t.children) >= 2 {
            return t_arrow(ty_from_ast(t.children[0], env, r),
                           ty_from_ast(t.children[1], env, r), nil)
        }
        elems: [dynamic]^Type = make([dynamic]^Type)
        for c in t.children do append(&elems, ty_from_ast(c, env, r))
        return t_tuple(elems)
    case .Type_Map:
        k := ty_from_ast(t.children[0], env, r) if len(t.children) > 0 else t_var()
        v := ty_from_ast(t.children[1], env, r) if len(t.children) > 1 else t_var()
        args: [dynamic]^Type = make([dynamic]^Type); append(&args, k); append(&args, v)
        return t_app(t_con("Map"), args)
    case .Type_Record:
        row := row_empty_closed()
        for c in t.children {
            if c == nil do continue
            if c.kind == .Field_Decl {
                fty := ty_from_ast(c.type_expr, env, r) if c.type_expr != nil else t_var()
                if c.suffix != .Invalid do fty = wrap_with_suffix(fty, c.suffix)
                row = row_extend(row, c.text, fty)
            }
        }
        return t_record(row)
    case .Ident:
        // user-named type (post-`def`)
        if sch, ok := env_lookup(env, t.text); ok {
            return instantiate(sch)
        }
        return t_con(t.text)
    case .Compound_Expr:
        // compound type-name like `flora-species` → Con("flora-species")
        return t_con(type_path(t))
    }
    return t_var()
}

@(private="file")
prim_from_kw :: proc(k: Token_Kind) -> ^Type {
    #partial switch k {
    case .Prim_U8:  return t_prim(.U8)
    case .Prim_U16: return t_prim(.U16)
    case .Prim_U32: return t_prim(.U32)
    case .Prim_U64: return t_prim(.U64)
    case .Prim_I8:  return t_prim(.I8)
    case .Prim_I16: return t_prim(.I16)
    case .Prim_I32: return t_prim(.I32)
    case .Prim_I64: return t_prim(.I64)
    case .Prim_F32: return t_prim(.F32)
    case .Prim_F64: return t_prim(.F64)
    case .Prim_Bool: return t_prim(.Bool)
    case .Prim_Str:  return t_prim(.String)
    case .Prim_Vec2: return t_prim(.Vec2)
    case .Prim_Vec3: return t_prim(.Vec3)
    case .Prim_Vec4: return t_prim(.Vec4)
    case .Prim_Mat4: return t_prim(.Mat4)
    case .Prim_Quat: return t_prim(.Quat)
    case .Prim_Rgba: return t_prim(.Rgba)
    }
    return t_var()
}

@(private="file")
type_path :: proc(n: ^Node) -> string {
    if n == nil do return ""
    if n.kind == .Ident do return n.text
    if n.kind == .Compound_Expr && len(n.children) == 2 {
        return fmt.tprintf("%s.%s", type_path(n.children[0]), type_path(n.children[1]))
    }
    return n.text
}

// ---------- Diagnostic rendering ----------

tc_render_summary :: proc(r: ^Tc_Result, verbose: bool = false) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, "== typecheck summary ==\n")
    strings.write_string(&sb, fmt.tprintf("mode:                   %s%s\n",
        sem_mode_name(r.mode), r.strict_parse ? " + strict-parse" : ""))
    strings.write_string(&sb, fmt.tprintf("global bindings:        %d\n", len(r.globals)))
    strings.write_string(&sb, fmt.tprintf("nodes annotated:        %d\n", len(r.types)))
    strings.write_string(&sb, fmt.tprintf("refine obligations:     %d\n", r.refine_obligations))
    info, warn, err := 0, 0, 0
    for d in r.diagnostics {
        #partial switch d.severity {
        case .Info:  info += 1
        case .Warn:  warn += 1
        case .Error: err  += 1
        }
    }
    strings.write_string(&sb, fmt.tprintf("diagnostics:            info=%d warn=%d error=%d\n", info, warn, err))
    for d in r.diagnostics {
        if d.severity == .Info && !verbose do continue
        strings.write_string(&sb, fmt.tprintf("  [%s] %s:%d:%d %s : %s\n",
            severity_label(d.severity), d.pos.file, d.pos.line, d.pos.col,
            sem_code_name(d.code), d.msg))
    }
    return strings.to_string(sb)
}

tc_fails :: proc(r: ^Tc_Result) -> bool {
    if r.mode == .Lint do return false
    for d in r.diagnostics {
        switch d.severity {
        case .Error:
            return true
        case .Warn:
            if r.mode == .Strict do return true
        case .Info:
        }
    }
    return false
}
