package cslparser

// § CSLv3 TYPE-CHECKER — UNIFICATION (T20.b Session-5)
// I> Robinson-style with level-based occurs-check speedup (OCaml-lineage)
// I> Leijen scoped-row unification for records + variants + effects
// W! occurs-check prevents infinite types (α = α → β)
// W! row-unification handles open/closed rows + fresh tail-var allocation
// R! ← handoff T20 pre-auth : bounded-fuel fallback on runaway unification

import "core:fmt"
import "core:strings"

// ---------- Unification result ----------

Unify_Error_Kind :: enum {
    Mismatch,       // structural : Int vs String
    Arity,          // Tuple arity differs
    Occurs,         // α occurs in T
    RowMissing,     // row label present in one but not other (closed)
    RowCycle,       // cyclic row-tail
    Fuel,           // bounded-fuel exhausted
}

Unify_Error :: struct {
    kind: Unify_Error_Kind,
    lhs:  ^Type,
    rhs:  ^Type,
    msg:  string,
}

// fuel budget — bounded-fuel fallback per T20 handoff
@(private="file")
FUEL_BUDGET :: 10_000

// ---------- Core unify ----------

unify :: proc(a, b: ^Type) -> (err: Maybe(Unify_Error)) {
    fuel := FUEL_BUDGET
    return unify_fuel(a, b, &fuel)
}

unify_fuel :: proc(a, b: ^Type, fuel: ^int) -> Maybe(Unify_Error) {
    if fuel^ <= 0 {
        return Unify_Error{kind = .Fuel, lhs = a, rhs = b,
            msg = fmt.tprintf("unification fuel exhausted (>%d steps)", FUEL_BUDGET)}
    }
    fuel^ -= 1

    ra := follow(a)
    rb := follow(b)
    if ra == rb do return nil   // ptr-equal shortcut

    // Var on either side
    if ra.kind == .Var {
        return bind_var(ra, rb)
    }
    if rb.kind == .Var {
        return bind_var(rb, ra)
    }

    // Different kind → mismatch
    if ra.kind != rb.kind {
        return Unify_Error{kind = .Mismatch, lhs = ra, rhs = rb,
            msg = fmt.tprintf("cannot unify %s with %s", type_repr(ra), type_repr(rb))}
    }

    #partial switch ra.kind {
    case .Prim:
        if ra.prim != rb.prim {
            return Unify_Error{kind = .Mismatch, lhs = ra, rhs = rb,
                msg = fmt.tprintf("primitive type mismatch: %s vs %s",
                    prim_name(ra.prim), prim_name(rb.prim))}
        }
    case .Arrow:
        if e := unify_fuel(ra.from, rb.from, fuel); e != nil do return e
        if e := unify_fuel(ra.to,   rb.to,   fuel); e != nil do return e
        // effect rows : unify if both present ; else skip (pure-by-absence)
        if ra.eff != nil && rb.eff != nil {
            if e := unify_row(ra.eff, rb.eff, fuel); e != nil do return e
        } else if ra.eff != nil || rb.eff != nil {
            // one pure, other with effects — treat as non-empty-row vs empty-closed
            a_row := ra.eff if ra.eff != nil else row_empty_closed()
            b_row := rb.eff if rb.eff != nil else row_empty_closed()
            if e := unify_row(a_row, b_row, fuel); e != nil do return e
        }
    case .Record, .Variant:
        if e := unify_row(ra.row, rb.row, fuel); e != nil do return e
    case .Refine:
        if e := unify_fuel(ra.base, rb.base, fuel); e != nil do return e
        // refinement predicate equality : string-equal for now ; T26 upgrades
        if ra.refine_pred != rb.refine_pred {
            // compatible-base, distinct-predicate : allow (subtype-like)
            // but emit a warning-equivalent via keeping narrower-on-left?
            // conservative : accept silently ; SMT layer will reason about φ.
        }
    case .Tagged:
        if e := unify_fuel(ra.tag_ty, rb.tag_ty, fuel); e != nil do return e
        if ra.tag_name != rb.tag_name {
            // different morpheme tags : allow if base unifies (structural)
        }
    case .Con:
        if ra.con_name != rb.con_name {
            return Unify_Error{kind = .Mismatch, lhs = ra, rhs = rb,
                msg = fmt.tprintf("type constructor mismatch: %s vs %s",
                    ra.con_name, rb.con_name)}
        }
        if len(ra.con_args) != len(rb.con_args) {
            return Unify_Error{kind = .Arity, lhs = ra, rhs = rb,
                msg = fmt.tprintf("arity mismatch: %s[%d] vs %s[%d]",
                    ra.con_name, len(ra.con_args), rb.con_name, len(rb.con_args))}
        }
        for i in 0 ..< len(ra.con_args) {
            if e := unify_fuel(ra.con_args[i], rb.con_args[i], fuel); e != nil do return e
        }
    case .Tuple:
        if len(ra.con_args) != len(rb.con_args) {
            return Unify_Error{kind = .Arity, lhs = ra, rhs = rb,
                msg = fmt.tprintf("tuple arity mismatch: (%d) vs (%d)",
                    len(ra.con_args), len(rb.con_args))}
        }
        for i in 0 ..< len(ra.con_args) {
            if e := unify_fuel(ra.con_args[i], rb.con_args[i], fuel); e != nil do return e
        }
    case .App:
        if e := unify_fuel(ra.base, rb.base, fuel); e != nil do return e
        if len(ra.con_args) != len(rb.con_args) {
            return Unify_Error{kind = .Arity, lhs = ra, rhs = rb,
                msg = fmt.tprintf("type-app arity mismatch")}
        }
        for i in 0 ..< len(ra.con_args) {
            if e := unify_fuel(ra.con_args[i], rb.con_args[i], fuel); e != nil do return e
        }
    case .Pi, .Sigma:
        if e := unify_fuel(ra.var_ty, rb.var_ty, fuel); e != nil do return e
        // α-rename via scheme-like instantiation for ret_ty (simplified here)
        if e := unify_fuel(ra.ret_ty, rb.ret_ty, fuel); e != nil do return e
    case .Forall:
        // scheme-to-scheme unify : unify bodies assuming same bound-set.
        // conservative : require same-arity ; unify bodies.
        if len(ra.bound) != len(rb.bound) {
            return Unify_Error{kind = .Arity, lhs = ra, rhs = rb,
                msg = "quantifier arity mismatch"}
        }
        if e := unify_fuel(ra.ret_ty, rb.ret_ty, fuel); e != nil do return e
    }
    return nil
}

// ---------- Var binding ----------

@(private="file")
bind_var :: proc(v, t: ^Type) -> Maybe(Unify_Error) {
    // v must be a Var (resolved)
    if v == t do return nil
    // occurs check
    if occurs(v.id, t) {
        return Unify_Error{kind = .Occurs, lhs = v, rhs = t,
            msg = fmt.tprintf("occurs check fails: α%d occurs in %s",
                int(v.id), type_repr(t))}
    }
    // level-based adjustment : lower every Var in t to min(its level, v.level)
    adjust_levels(t, v.level)
    v.link = t
    return nil
}

@(private="file")
occurs :: proc(id: Type_Id, t: ^Type) -> bool {
    if t == nil do return false
    r := follow(t)
    #partial switch r.kind {
    case .Var:
        return r.id == id
    case .Arrow:
        return occurs(id, r.from) || occurs(id, r.to) || (r.eff != nil && occurs_row(id, r.eff))
    case .Record, .Variant:
        return r.row != nil && occurs_row(id, r.row)
    case .Refine:
        return occurs(id, r.base)
    case .Tagged:
        return occurs(id, r.tag_ty)
    case .Pi, .Sigma:
        return occurs(id, r.var_ty) || occurs(id, r.ret_ty)
    case .Forall:
        return occurs(id, r.ret_ty)
    case .Con, .Tuple:
        for a in r.con_args do if occurs(id, a) do return true
    case .App:
        if occurs(id, r.base) do return true
        for a in r.con_args do if occurs(id, a) do return true
    }
    return false
}

@(private="file")
occurs_row :: proc(id: Type_Id, r: ^Row) -> bool {
    if r == nil do return false
    for lbl in r.labels do if occurs(id, lbl.ty) do return true
    return r.tail != nil && occurs(id, r.tail)
}

@(private="file")
adjust_levels :: proc(t: ^Type, lvl: Level) {
    if t == nil do return
    r := follow(t)
    #partial switch r.kind {
    case .Var:
        if int(r.level) > int(lvl) do r.level = lvl
    case .Arrow:
        adjust_levels(r.from, lvl)
        adjust_levels(r.to, lvl)
        if r.eff != nil do adjust_levels_row(r.eff, lvl)
    case .Record, .Variant:
        if r.row != nil do adjust_levels_row(r.row, lvl)
    case .Refine:
        adjust_levels(r.base, lvl)
    case .Tagged:
        adjust_levels(r.tag_ty, lvl)
    case .Pi, .Sigma:
        adjust_levels(r.var_ty, lvl)
        adjust_levels(r.ret_ty, lvl)
    case .Forall:
        adjust_levels(r.ret_ty, lvl)
    case .Con, .Tuple:
        for a in r.con_args do adjust_levels(a, lvl)
    case .App:
        adjust_levels(r.base, lvl)
        for a in r.con_args do adjust_levels(a, lvl)
    }
}

@(private="file")
adjust_levels_row :: proc(r: ^Row, lvl: Level) {
    if r == nil do return
    for lbl in r.labels do adjust_levels(lbl.ty, lvl)
    if r.tail != nil do adjust_levels(r.tail, lvl)
}

// ---------- Row unification (Leijen scoped-rows) ----------

unify_row :: proc(a, b: ^Row, fuel: ^int) -> Maybe(Unify_Error) {
    if fuel^ <= 0 {
        return Unify_Error{kind = .Fuel, msg = "row unification fuel exhausted"}
    }
    fuel^ -= 1
    if a == b do return nil

    // build label-maps for quick lookup
    a_map: map[string]^Type; a_map = make(map[string]^Type); defer delete(a_map)
    b_map: map[string]^Type; b_map = make(map[string]^Type); defer delete(b_map)
    for lbl in a.labels do a_map[lbl.name] = lbl.ty
    for lbl in b.labels do b_map[lbl.name] = lbl.ty

    // Unify labels present in both sides
    for name, ty_a in a_map {
        if ty_b, found := b_map[name]; found {
            if e := unify_fuel(ty_a, ty_b, fuel); e != nil do return e
        }
    }

    // Labels in A missing from B → need extension on B's tail (if open) or fail (closed)
    missing_from_b: [dynamic]Row_Label = make([dynamic]Row_Label)
    defer delete(missing_from_b)
    for name, ty in a_map {
        if _, found := b_map[name]; !found {
            append(&missing_from_b, Row_Label{name = name, ty = ty})
        }
    }
    missing_from_a: [dynamic]Row_Label = make([dynamic]Row_Label)
    defer delete(missing_from_a)
    for name, ty in b_map {
        if _, found := a_map[name]; !found {
            append(&missing_from_a, Row_Label{name = name, ty = ty})
        }
    }

    // If A's tail is closed and B has labels A doesn't have → mismatch.
    if a.tail == nil && len(missing_from_a) > 0 {
        names: [dynamic]string = make([dynamic]string); defer delete(names)
        for l in missing_from_a do append(&names, l.name)
        return Unify_Error{kind = .RowMissing,
            msg = fmt.tprintf("row missing labels in closed side: %v", names)}
    }
    if b.tail == nil && len(missing_from_b) > 0 {
        names: [dynamic]string = make([dynamic]string); defer delete(names)
        for l in missing_from_b do append(&names, l.name)
        return Unify_Error{kind = .RowMissing,
            msg = fmt.tprintf("row missing labels in closed side: %v", names)}
    }

    // Both open : allocate fresh shared tail.
    if a.tail != nil && b.tail != nil {
        shared := t_var()
        // A's tail must unify with (missing-from-A labels + shared)
        ta_row := new(Row)
        ta_row.labels = make([dynamic]Row_Label)
        for l in missing_from_a do append(&ta_row.labels, l)
        ta_row.tail = shared
        // pack as Record-type so we can unify through a Type wrapper
        if e := unify_fuel(a.tail, t_record(ta_row), fuel); e != nil do return e

        tb_row := new(Row)
        tb_row.labels = make([dynamic]Row_Label)
        for l in missing_from_b do append(&tb_row.labels, l)
        tb_row.tail = shared
        if e := unify_fuel(b.tail, t_record(tb_row), fuel); e != nil do return e
        return nil
    }

    // A open, B closed : A's tail absorbs missing-from-A ; B must supply nothing missing-from-B.
    if a.tail != nil {
        ta_row := new(Row)
        ta_row.labels = make([dynamic]Row_Label)
        for l in missing_from_a do append(&ta_row.labels, l)
        ta_row.tail = nil
        if e := unify_fuel(a.tail, t_record(ta_row), fuel); e != nil do return e
        return nil
    }

    // B open, A closed : symmetrical
    if b.tail != nil {
        tb_row := new(Row)
        tb_row.labels = make([dynamic]Row_Label)
        for l in missing_from_b do append(&tb_row.labels, l)
        tb_row.tail = nil
        if e := unify_fuel(b.tail, t_record(tb_row), fuel); e != nil do return e
        return nil
    }

    // Both closed : already verified no missing labels above.
    return nil
}

// ---------- API helpers ----------

format_unify_err :: proc(e: Unify_Error) -> string {
    prefix: string
    switch e.kind {
    case .Mismatch:   prefix = "type-mismatch"
    case .Arity:      prefix = "arity"
    case .Occurs:     prefix = "occurs-check"
    case .RowMissing: prefix = "row-missing-label"
    case .RowCycle:   prefix = "row-cycle"
    case .Fuel:       prefix = "unification-fuel"
    }
    return fmt.tprintf("[%s] %s", prefix, e.msg)
}
