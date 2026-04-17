package cslparser

// § CSLv3 TYPE-CHECKER — TYPE SYSTEM (T20.a Session-5)
// I> Type + Row + Subst + Scheme + Env + constructors
// I> bidirectional HM (Dunfield-Krishnaswami) + Leijen scoped-rows + refinement tags
// W! level-based unification speedup (OCaml-lineage)
// W! refinement obligations deferred to SMT queue (future T26)
// R! ← DECISIONS Q20.1 : tagged-union Type with ptr-sharing for vars

import "core:fmt"
import "core:strings"

// ---------- Type IDs / levels ----------

Type_Id :: distinct int      // globally-unique type-var id
Level   :: distinct int      // HM level for generalization (Remy)

@(private="file")
g_next_tyvar: Type_Id = 0

fresh_tyvar_id :: proc() -> Type_Id {
    g_next_tyvar = Type_Id(int(g_next_tyvar) + 1)
    return g_next_tyvar
}

@(private="file")
g_current_level: Level = 0

enter_level :: proc() { g_current_level = Level(int(g_current_level) + 1) }
exit_level  :: proc() { g_current_level = Level(int(g_current_level) - 1) }
current_level :: proc() -> Level { return g_current_level }

// ---------- Primitive types ----------

Prim_Ty :: enum {
    Int, I8, I16, I32, I64,
    U8, U16, U32, U64,
    Float, F32, F64,
    String, Bool, Symbol, Unit,
    Vec2, Vec3, Vec4, Mat4, Quat, Rgba,
}

prim_name :: proc(p: Prim_Ty) -> string {
    switch p {
    case .Int:    return "Int"
    case .I8:     return "i8"
    case .I16:    return "i16"
    case .I32:    return "i32"
    case .I64:    return "i64"
    case .U8:     return "u8"
    case .U16:    return "u16"
    case .U32:    return "u32"
    case .U64:    return "u64"
    case .Float:  return "Float"
    case .F32:    return "f32"
    case .F64:    return "f64"
    case .String: return "str"
    case .Bool:   return "bool"
    case .Symbol: return "Symbol"
    case .Unit:   return "Unit"
    case .Vec2:   return "vec2"
    case .Vec3:   return "vec3"
    case .Vec4:   return "vec4"
    case .Mat4:   return "mat4"
    case .Quat:   return "quat"
    case .Rgba:   return "rgba"
    }
    return "?"
}

// ---------- Type variants ----------

Type_Kind :: enum {
    Var,        // α unification variable
    Prim,       // base types
    Arrow,      // T1 -> T2 / ε
    Record,     // {ℓ:T, ... | ρ}
    Variant,    // [ℓ:T | ρ]
    Forall,     // ∀ α. T
    Pi,         // Π x:T. T'
    Sigma,      // Σ x:T. T'  (declared ; full support stub)
    Refine,     // {v:T | φ}
    Tagged,     // T^tag (morpheme refinement)
    Con,        // nominal type constructor (user-def via `def`)
    Tuple,      // (T1, T2, ...)
    App,        // F[T1, T2, ...] — type application (e.g. Vec[n, α])
}

Row :: struct {
    // Leijen scoped-row : an open row has tail = ptr-to-var,
    // a closed row has tail = nil.
    labels: [dynamic]Row_Label,
    tail:   ^Type,   // nil (closed) OR ptr-to-Var type (open)
}

Row_Label :: struct {
    name: string,
    ty:   ^Type,
}

Type :: struct {
    kind:  Type_Kind,

    // Var
    id:    Type_Id,
    level: Level,
    link:  ^Type,   // non-nil ⇒ this var has been unified (follow the link)

    // Prim
    prim:  Prim_Ty,

    // Arrow
    from:  ^Type,
    to:    ^Type,
    eff:   ^Row,   // effect-row (nil = pure)

    // Record / Variant
    row:   ^Row,

    // Forall / Pi / Sigma
    var_name: string,
    var_ty:   ^Type,
    ret_ty:   ^Type,
    bound:    [dynamic]Type_Id,   // Forall : generalised var ids

    // Refine
    base:     ^Type,
    refine_pred: string,   // textual tag (T26 : upgrade to expression node)

    // Tagged (morpheme)
    tag_ty:   ^Type,
    tag_name: string,

    // Con : nominal user-def
    con_name: string,
    con_args: [dynamic]^Type,   // type-args for generic Con
}

// ---------- constructors ----------

t_var :: proc() -> ^Type {
    t := new(Type)
    t.kind  = .Var
    t.id    = fresh_tyvar_id()
    t.level = current_level()
    t.link  = nil
    return t
}

t_prim :: proc(p: Prim_Ty) -> ^Type {
    t := new(Type)
    t.kind = .Prim
    t.prim = p
    return t
}

t_arrow :: proc(from, to: ^Type, eff: ^Row = nil) -> ^Type {
    t := new(Type)
    t.kind = .Arrow
    t.from = from
    t.to   = to
    t.eff  = eff
    return t
}

t_record :: proc(r: ^Row) -> ^Type {
    t := new(Type)
    t.kind = .Record
    t.row  = r
    return t
}

t_variant :: proc(r: ^Row) -> ^Type {
    t := new(Type)
    t.kind = .Variant
    t.row  = r
    return t
}

t_forall :: proc(bound: [dynamic]Type_Id, body: ^Type) -> ^Type {
    t := new(Type)
    t.kind   = .Forall
    t.bound  = bound
    t.ret_ty = body
    return t
}

t_pi :: proc(name: string, var_ty, ret_ty: ^Type) -> ^Type {
    t := new(Type)
    t.kind = .Pi
    t.var_name = name
    t.var_ty   = var_ty
    t.ret_ty   = ret_ty
    return t
}

t_sigma :: proc(name: string, var_ty, ret_ty: ^Type) -> ^Type {
    t := new(Type)
    t.kind = .Sigma
    t.var_name = name
    t.var_ty   = var_ty
    t.ret_ty   = ret_ty
    return t
}

t_refine :: proc(base: ^Type, pred: string) -> ^Type {
    t := new(Type)
    t.kind = .Refine
    t.base = base
    t.refine_pred = pred
    return t
}

t_tagged :: proc(base: ^Type, tag: string) -> ^Type {
    t := new(Type)
    t.kind = .Tagged
    t.tag_ty   = base
    t.tag_name = tag
    return t
}

t_con :: proc(name: string, args: [dynamic]^Type = nil) -> ^Type {
    t := new(Type)
    t.kind = .Con
    t.con_name = name
    if args != nil do t.con_args = args
    return t
}

t_tuple :: proc(elems: [dynamic]^Type) -> ^Type {
    t := new(Type)
    t.kind = .Tuple
    t.con_args = elems
    return t
}

t_app :: proc(head: ^Type, args: [dynamic]^Type) -> ^Type {
    t := new(Type)
    t.kind = .App
    t.base = head
    t.con_args = args
    return t
}

// ---------- Row constructors ----------

row_empty_closed :: proc() -> ^Row {
    r := new(Row)
    r.labels = make([dynamic]Row_Label)
    r.tail = nil
    return r
}

row_empty_open :: proc() -> ^Row {
    r := new(Row)
    r.labels = make([dynamic]Row_Label)
    r.tail = t_var()
    return r
}

row_extend :: proc(parent: ^Row, name: string, ty: ^Type) -> ^Row {
    r := new(Row)
    r.labels = make([dynamic]Row_Label)
    append(&r.labels, Row_Label{name = name, ty = ty})
    for lbl in parent.labels do append(&r.labels, lbl)
    r.tail = parent.tail
    return r
}

// Unit type (commonly useful)
t_unit :: proc() -> ^Type { return t_prim(.Unit) }

// ---------- Pretty-printing (for diagnostics + JSON) ----------

type_repr :: proc(t: ^Type) -> string {
    if t == nil do return "<nil>"
    sb := strings.builder_make()
    type_repr_into(&sb, t)
    return strings.to_string(sb)
}

@(private="file")
type_repr_into :: proc(sb: ^strings.Builder, t: ^Type) {
    if t == nil {
        strings.write_string(sb, "<nil>")
        return
    }
    // follow unification link
    resolved := follow(t)
    #partial switch resolved.kind {
    case .Var:
        strings.write_string(sb, fmt.tprintf("α%d", int(resolved.id)))
    case .Prim:
        strings.write_string(sb, prim_name(resolved.prim))
    case .Arrow:
        type_repr_into(sb, resolved.from)
        strings.write_string(sb, " -> ")
        type_repr_into(sb, resolved.to)
        if resolved.eff != nil && (len(resolved.eff.labels) > 0 || resolved.eff.tail != nil) {
            strings.write_string(sb, " /")
            row_repr_into(sb, resolved.eff)
        }
    case .Record:
        strings.write_rune(sb, '{')
        row_repr_into(sb, resolved.row)
        strings.write_rune(sb, '}')
    case .Variant:
        strings.write_rune(sb, '[')
        row_repr_into(sb, resolved.row)
        strings.write_rune(sb, ']')
    case .Forall:
        strings.write_string(sb, "∀")
        for id, i in resolved.bound {
            if i > 0 do strings.write_rune(sb, ',')
            strings.write_string(sb, fmt.tprintf("α%d", int(id)))
        }
        strings.write_rune(sb, '.')
        type_repr_into(sb, resolved.ret_ty)
    case .Pi:
        strings.write_string(sb, "Π")
        strings.write_string(sb, resolved.var_name)
        strings.write_rune(sb, ':')
        type_repr_into(sb, resolved.var_ty)
        strings.write_rune(sb, '.')
        type_repr_into(sb, resolved.ret_ty)
    case .Sigma:
        strings.write_string(sb, "Σ")
        strings.write_string(sb, resolved.var_name)
        strings.write_rune(sb, ':')
        type_repr_into(sb, resolved.var_ty)
        strings.write_rune(sb, '.')
        type_repr_into(sb, resolved.ret_ty)
    case .Refine:
        strings.write_rune(sb, '{')
        strings.write_string(sb, "v:")
        type_repr_into(sb, resolved.base)
        strings.write_string(sb, " | ")
        strings.write_string(sb, resolved.refine_pred)
        strings.write_rune(sb, '}')
    case .Tagged:
        type_repr_into(sb, resolved.tag_ty)
        strings.write_rune(sb, '^')
        strings.write_string(sb, resolved.tag_name)
    case .Con:
        strings.write_string(sb, resolved.con_name)
        if len(resolved.con_args) > 0 {
            strings.write_rune(sb, '[')
            for a, i in resolved.con_args {
                if i > 0 do strings.write_string(sb, ", ")
                type_repr_into(sb, a)
            }
            strings.write_rune(sb, ']')
        }
    case .Tuple:
        strings.write_rune(sb, '(')
        for e, i in resolved.con_args {
            if i > 0 do strings.write_string(sb, ", ")
            type_repr_into(sb, e)
        }
        strings.write_rune(sb, ')')
    case .App:
        type_repr_into(sb, resolved.base)
        strings.write_rune(sb, '[')
        for a, i in resolved.con_args {
            if i > 0 do strings.write_string(sb, ", ")
            type_repr_into(sb, a)
        }
        strings.write_rune(sb, ']')
    }
}

@(private="file")
row_repr_into :: proc(sb: ^strings.Builder, r: ^Row) {
    if r == nil {
        strings.write_string(sb, "⟨⟩")
        return
    }
    for lbl, i in r.labels {
        if i > 0 do strings.write_string(sb, ", ")
        strings.write_string(sb, lbl.name)
        strings.write_rune(sb, ':')
        type_repr_into(sb, lbl.ty)
    }
    if r.tail != nil {
        if len(r.labels) > 0 do strings.write_string(sb, " | ")
        type_repr_into(sb, r.tail)
    }
}

// Follow unification links to the representative (path compression optional).
follow :: proc(t: ^Type) -> ^Type {
    if t == nil do return nil
    cur := t
    for cur.kind == .Var && cur.link != nil {
        cur = cur.link
    }
    return cur
}

// ---------- Type Scheme (polytype) ----------

Scheme :: struct {
    vars: [dynamic]Type_Id,  // quantified
    body: ^Type,
}

scheme_mono :: proc(t: ^Type) -> Scheme {
    return Scheme{vars = make([dynamic]Type_Id), body = t}
}

// ---------- Environment ----------

Env :: struct {
    bindings: map[string]Scheme,
    parent:   ^Env,
}

env_new :: proc(parent: ^Env = nil) -> ^Env {
    e := new(Env)
    e.bindings = make(map[string]Scheme)
    e.parent = parent
    return e
}

env_lookup :: proc(e: ^Env, name: string) -> (sch: Scheme, ok: bool) {
    cur := e
    for cur != nil {
        if s, found := cur.bindings[name]; found {
            return s, true
        }
        cur = cur.parent
    }
    return Scheme{}, false
}

env_extend :: proc(e: ^Env, name: string, sch: Scheme) {
    e.bindings[name] = sch
}

// ---------- Substitution ----------
// Subst is implemented via in-place link mutation on Type_Var nodes.
// apply_subst follows links; no explicit map needed.

apply :: proc(t: ^Type) -> ^Type {
    if t == nil do return nil
    resolved := follow(t)
    #partial switch resolved.kind {
    case .Arrow:
        resolved.from = apply(resolved.from)
        resolved.to   = apply(resolved.to)
        if resolved.eff != nil do apply_row(resolved.eff)
    case .Record, .Variant:
        if resolved.row != nil do apply_row(resolved.row)
    case .Refine:
        resolved.base = apply(resolved.base)
    case .Tagged:
        resolved.tag_ty = apply(resolved.tag_ty)
    case .Forall, .Pi, .Sigma:
        resolved.var_ty = apply(resolved.var_ty)
        resolved.ret_ty = apply(resolved.ret_ty)
    case .Con, .Tuple:
        for i in 0 ..< len(resolved.con_args) {
            resolved.con_args[i] = apply(resolved.con_args[i])
        }
    case .App:
        resolved.base = apply(resolved.base)
        for i in 0 ..< len(resolved.con_args) {
            resolved.con_args[i] = apply(resolved.con_args[i])
        }
    }
    return resolved
}

apply_row :: proc(r: ^Row) {
    if r == nil do return
    for i in 0 ..< len(r.labels) {
        r.labels[i].ty = apply(r.labels[i].ty)
    }
    if r.tail != nil {
        r.tail = apply(r.tail)
    }
}

// ---------- Free type variables ----------

ftv :: proc(t: ^Type, out: ^map[Type_Id]bool) {
    if t == nil do return
    resolved := follow(t)
    #partial switch resolved.kind {
    case .Var:
        out^[resolved.id] = true
    case .Arrow:
        ftv(resolved.from, out)
        ftv(resolved.to, out)
        if resolved.eff != nil do ftv_row(resolved.eff, out)
    case .Record, .Variant:
        if resolved.row != nil do ftv_row(resolved.row, out)
    case .Refine:
        ftv(resolved.base, out)
    case .Tagged:
        ftv(resolved.tag_ty, out)
    case .Forall:
        inner: map[Type_Id]bool
        inner = make(map[Type_Id]bool)
        defer delete(inner)
        ftv(resolved.ret_ty, &inner)
        for id in resolved.bound do delete_key(&inner, id)
        for id in inner do out^[id] = true
    case .Pi, .Sigma:
        ftv(resolved.var_ty, out)
        ftv(resolved.ret_ty, out)
    case .Con, .Tuple:
        for a in resolved.con_args do ftv(a, out)
    case .App:
        ftv(resolved.base, out)
        for a in resolved.con_args do ftv(a, out)
    }
}

ftv_row :: proc(r: ^Row, out: ^map[Type_Id]bool) {
    if r == nil do return
    for lbl in r.labels do ftv(lbl.ty, out)
    if r.tail != nil do ftv(r.tail, out)
}

// ---------- Generalization + Instantiation ----------
// generalize(env, t) : quantify ftv(t) \ ftv(env) at current_level.
// instantiate(s)     : fresh vars for s.vars ; walk body replacing.

generalize :: proc(env: ^Env, t: ^Type) -> Scheme {
    env_vars: map[Type_Id]bool
    env_vars = make(map[Type_Id]bool)
    defer delete(env_vars)
    cur := env
    for cur != nil {
        for _, sch in cur.bindings {
            ftv(sch.body, &env_vars)
        }
        cur = cur.parent
    }
    t_vars: map[Type_Id]bool
    t_vars = make(map[Type_Id]bool)
    defer delete(t_vars)
    ftv(t, &t_vars)
    bound: [dynamic]Type_Id = make([dynamic]Type_Id)
    for id in t_vars {
        if _, in_env := env_vars[id]; !in_env {
            append(&bound, id)
        }
    }
    return Scheme{vars = bound, body = t}
}

instantiate :: proc(s: Scheme) -> ^Type {
    if len(s.vars) == 0 do return s.body
    subst: map[Type_Id]^Type
    subst = make(map[Type_Id]^Type)
    defer delete(subst)
    for id in s.vars {
        subst[id] = t_var()
    }
    return rebuild(s.body, &subst)
}

@(private="file")
rebuild :: proc(t: ^Type, subst: ^map[Type_Id]^Type) -> ^Type {
    if t == nil do return nil
    resolved := follow(t)
    #partial switch resolved.kind {
    case .Var:
        if repl, found := subst^[resolved.id]; found do return repl
        return resolved
    case .Arrow:
        eff := resolved.eff
        return t_arrow(rebuild(resolved.from, subst), rebuild(resolved.to, subst), eff)
    case .Record:
        return t_record(rebuild_row(resolved.row, subst))
    case .Variant:
        return t_variant(rebuild_row(resolved.row, subst))
    case .Refine:
        return t_refine(rebuild(resolved.base, subst), resolved.refine_pred)
    case .Tagged:
        return t_tagged(rebuild(resolved.tag_ty, subst), resolved.tag_name)
    case .Pi:
        return t_pi(resolved.var_name, rebuild(resolved.var_ty, subst), rebuild(resolved.ret_ty, subst))
    case .Sigma:
        return t_sigma(resolved.var_name, rebuild(resolved.var_ty, subst), rebuild(resolved.ret_ty, subst))
    case .Con:
        args: [dynamic]^Type = make([dynamic]^Type)
        for a in resolved.con_args do append(&args, rebuild(a, subst))
        return t_con(resolved.con_name, args)
    case .Tuple:
        args: [dynamic]^Type = make([dynamic]^Type)
        for a in resolved.con_args do append(&args, rebuild(a, subst))
        return t_tuple(args)
    case .App:
        args: [dynamic]^Type = make([dynamic]^Type)
        for a in resolved.con_args do append(&args, rebuild(a, subst))
        return t_app(rebuild(resolved.base, subst), args)
    }
    return resolved
}

@(private="file")
rebuild_row :: proc(r: ^Row, subst: ^map[Type_Id]^Type) -> ^Row {
    if r == nil do return nil
    new_r := new(Row)
    new_r.labels = make([dynamic]Row_Label)
    for lbl in r.labels {
        append(&new_r.labels, Row_Label{name = lbl.name, ty = rebuild(lbl.ty, subst)})
    }
    if r.tail != nil do new_r.tail = rebuild(r.tail, subst)
    return new_r
}
