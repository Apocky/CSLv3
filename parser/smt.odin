package cslparser

// § CSLv3 SMT FORMULA AST (T26.a Session-7)
// I> SMT-LIB2-aligned ast : Formula + Sort + Theory + Quantifier + Trigger
// I> tagged-union Formula ; Sort is small-enum + parameterized BitVec/Array
// I> all op-names are canonical SMT-LIB2 strings ← emit-layer concatenates literally
// I> theories : QF_LIA / QF_LRA / QF_UF / AUFLIA / AUFLIRA ← solver-logic selector
// R! ← CVC5 + Z3 both SMT-LIB2-native ; no C-FFI required

import "core:fmt"
import "core:strings"

// ---------- Sort (type) ----------

Sort_Kind :: enum {
    Bool,
    Int,
    Real,
    BitVec,        // width in .width
    Array,         // .idx → .elem
    Sym,           // uninterpreted user-defined sort (e.g. "MorphTag")
}

Sort :: struct {
    kind:  Sort_Kind,
    width: int,       // BitVec
    idx:   ^Sort,     // Array
    elem:  ^Sort,     // Array
    name:  string,    // Sym
}

s_bool   :: proc() -> ^Sort { s := new(Sort) ; s.kind = .Bool ; return s }
s_int    :: proc() -> ^Sort { s := new(Sort) ; s.kind = .Int  ; return s }
s_real   :: proc() -> ^Sort { s := new(Sort) ; s.kind = .Real ; return s }
s_bitvec :: proc(w: int) -> ^Sort {
    s := new(Sort) ; s.kind = .BitVec ; s.width = w ; return s
}
s_array  :: proc(idx, elem: ^Sort) -> ^Sort {
    s := new(Sort) ; s.kind = .Array ; s.idx = idx ; s.elem = elem ; return s
}
s_sym    :: proc(name: string) -> ^Sort {
    s := new(Sort) ; s.kind = .Sym ; s.name = strings.clone(name) ; return s
}

sort_eq :: proc(a, b: ^Sort) -> bool {
    if a == nil || b == nil do return a == b
    if a == b do return true
    if a.kind != b.kind do return false
    #partial switch a.kind {
    case .BitVec: return a.width == b.width
    case .Array:  return sort_eq(a.idx, b.idx) && sort_eq(a.elem, b.elem)
    case .Sym:    return a.name == b.name
    }
    return true
}

sort_repr :: proc(s: ^Sort) -> string {
    if s == nil do return "?"
    switch s.kind {
    case .Bool:   return "Bool"
    case .Int:    return "Int"
    case .Real:   return "Real"
    case .BitVec: return fmt.tprintf("(_ BitVec %d)", s.width)
    case .Array:  return fmt.tprintf("(Array %s %s)", sort_repr(s.idx), sort_repr(s.elem))
    case .Sym:    return s.name
    }
    return "?"
}

// ---------- Theory selection ----------

Theory :: enum {
    QF_UF,      // quantifier-free uninterpreted-functions only
    QF_LIA,     // QF + linear-integer-arith
    QF_LRA,     // QF + linear-real-arith
    QF_NIA,     // QF + non-linear-integer  (undecidable in general)
    QF_NRA,     // QF + non-linear-real    (decidable-via-CAD)
    QF_BV,      // QF + bitvectors
    QF_UFLIA,   // QF + UF + LIA
    QF_UFLRA,   // QF + UF + LRA
    AUFLIA,     // +Array +UF +LIA +Quant
    AUFLIRA,    // +Array +UF +LIA +LRA +Quant
    ALL,        // fallback — any logic
}

theory_logic_name :: proc(t: Theory) -> string {
    switch t {
    case .QF_UF:   return "QF_UF"
    case .QF_LIA:  return "QF_LIA"
    case .QF_LRA:  return "QF_LRA"
    case .QF_NIA:  return "QF_NIA"
    case .QF_NRA:  return "QF_NRA"
    case .QF_BV:   return "QF_BV"
    case .QF_UFLIA: return "QF_UFLIA"
    case .QF_UFLRA: return "QF_UFLRA"
    case .AUFLIA:  return "AUFLIA"
    case .AUFLIRA: return "AUFLIRA"
    case .ALL:     return "ALL"
    }
    return "ALL"
}

// ---------- Formula AST ----------

Formula_Kind :: enum {
    Var,     // bound/free variable reference
    BoolC,   // true / false
    IntC,    // integer literal
    RealC,   // rational literal (num / den)
    BvC,     // bitvector literal (value + width)
    Apply,   // (op args...) — op in {and,or,not,=>,=,distinct,<,<=,>,>=,+,-,*,div,mod, bv-ops, select,store, or UF-name}
    Ite,     // (ite c t e)
    Let,     // (let ((x e)...) body)
    Quant,   // (forall/exists ((x1 T1)...) body [:pattern ...])
}

Quant_Kind :: enum { Forall, Exists }

Binding :: struct {
    name: string,
    sort: ^Sort,
}

Formula :: struct {
    kind: Formula_Kind,
    sort: ^Sort,            // inferred during build ; used by emit for decl-fun

    // Var
    name:     string,

    // BoolC / IntC / RealC / BvC
    b_val:    bool,
    i_val:    i64,
    r_num:    i64,
    r_den:    i64,
    bv_width: int,

    // Apply
    op:       string,
    args:     [dynamic]^Formula,

    // Ite
    cond:     ^Formula,
    th:       ^Formula,
    el:       ^Formula,

    // Let / Quant
    let_bindings: [dynamic]Let_Binding,
    body:         ^Formula,
    quant_kind:   Quant_Kind,
    quant_vars:   [dynamic]Binding,
    triggers:     [dynamic][dynamic]^Formula,   // each trigger = list of patterns
}

Let_Binding :: struct {
    name: string,
    expr: ^Formula,
}

// ---------- Formula constructors ----------

f_var :: proc(name: string, sort: ^Sort) -> ^Formula {
    f := new(Formula)
    f.kind = .Var
    f.name = strings.clone(name)
    f.sort = sort
    return f
}

f_true :: proc() -> ^Formula {
    f := new(Formula) ; f.kind = .BoolC ; f.b_val = true  ; f.sort = s_bool() ; return f
}

f_false :: proc() -> ^Formula {
    f := new(Formula) ; f.kind = .BoolC ; f.b_val = false ; f.sort = s_bool() ; return f
}

f_int :: proc(v: i64) -> ^Formula {
    f := new(Formula) ; f.kind = .IntC ; f.i_val = v ; f.sort = s_int() ; return f
}

f_real :: proc(num, den: i64) -> ^Formula {
    f := new(Formula) ; f.kind = .RealC ; f.r_num = num ; f.r_den = den ; f.sort = s_real()
    return f
}

f_bv :: proc(v: i64, width: int) -> ^Formula {
    f := new(Formula)
    f.kind = .BvC ; f.i_val = v ; f.bv_width = width ; f.sort = s_bitvec(width)
    return f
}

f_apply :: proc(op: string, sort: ^Sort, args: ..^Formula) -> ^Formula {
    f := new(Formula)
    f.kind = .Apply
    f.op   = strings.clone(op)
    f.sort = sort
    f.args = make([dynamic]^Formula, 0, len(args))
    for a in args do append(&f.args, a)
    return f
}

f_applyv :: proc(op: string, sort: ^Sort, args: [dynamic]^Formula) -> ^Formula {
    f := new(Formula)
    f.kind = .Apply
    f.op   = strings.clone(op)
    f.sort = sort
    f.args = args
    return f
}

f_not :: proc(x: ^Formula) -> ^Formula {
    if x.kind == .BoolC do return f_false() if x.b_val else f_true()
    return f_apply("not", s_bool(), x)
}

f_and :: proc(xs: ..^Formula) -> ^Formula {
    if len(xs) == 0 do return f_true()
    if len(xs) == 1 do return xs[0]
    return f_apply("and", s_bool(), ..xs)
}

f_or :: proc(xs: ..^Formula) -> ^Formula {
    if len(xs) == 0 do return f_false()
    if len(xs) == 1 do return xs[0]
    return f_apply("or", s_bool(), ..xs)
}

f_implies :: proc(a, b: ^Formula) -> ^Formula { return f_apply("=>",       s_bool(), a, b) }
f_eq      :: proc(a, b: ^Formula) -> ^Formula { return f_apply("=",        s_bool(), a, b) }
f_neq     :: proc(a, b: ^Formula) -> ^Formula { return f_apply("distinct", s_bool(), a, b) }
f_lt      :: proc(a, b: ^Formula) -> ^Formula { return f_apply("<",        s_bool(), a, b) }
f_le      :: proc(a, b: ^Formula) -> ^Formula { return f_apply("<=",       s_bool(), a, b) }
f_gt      :: proc(a, b: ^Formula) -> ^Formula { return f_apply(">",        s_bool(), a, b) }
f_ge      :: proc(a, b: ^Formula) -> ^Formula { return f_apply(">=",       s_bool(), a, b) }

f_add :: proc(a, b: ^Formula) -> ^Formula {
    s := a.sort if a.sort != nil else s_int()
    return f_apply("+", s, a, b)
}
f_sub :: proc(a, b: ^Formula) -> ^Formula {
    s := a.sort if a.sort != nil else s_int()
    return f_apply("-", s, a, b)
}
f_mul :: proc(a, b: ^Formula) -> ^Formula {
    s := a.sort if a.sort != nil else s_int()
    return f_apply("*", s, a, b)
}
f_div_i :: proc(a, b: ^Formula) -> ^Formula { return f_apply("div", s_int(), a, b) }
f_mod_i :: proc(a, b: ^Formula) -> ^Formula { return f_apply("mod", s_int(), a, b) }
f_div_r :: proc(a, b: ^Formula) -> ^Formula { return f_apply("/",   s_real(), a, b) }
f_neg   :: proc(a: ^Formula) -> ^Formula {
    s := a.sort if a.sort != nil else s_int()
    return f_apply("-", s, a)
}

f_ite :: proc(cond, th, el: ^Formula) -> ^Formula {
    f := new(Formula)
    f.kind = .Ite
    f.cond = cond
    f.th   = th
    f.el   = el
    f.sort = th.sort if th.sort != nil else el.sort
    return f
}

f_select :: proc(arr, idx: ^Formula) -> ^Formula {
    s := arr.sort.elem if arr.sort != nil && arr.sort.kind == .Array else nil
    return f_apply("select", s, arr, idx)
}
f_store :: proc(arr, idx, v: ^Formula) -> ^Formula {
    return f_apply("store", arr.sort, arr, idx, v)
}

f_forall :: proc(vars: [dynamic]Binding, body: ^Formula) -> ^Formula {
    f := new(Formula)
    f.kind = .Quant
    f.quant_kind = .Forall
    f.quant_vars = vars
    f.body = body
    f.sort = s_bool()
    f.triggers = make([dynamic][dynamic]^Formula)
    return f
}

f_exists :: proc(vars: [dynamic]Binding, body: ^Formula) -> ^Formula {
    f := new(Formula)
    f.kind = .Quant
    f.quant_kind = .Exists
    f.quant_vars = vars
    f.body = body
    f.sort = s_bool()
    f.triggers = make([dynamic][dynamic]^Formula)
    return f
}

quant_add_trigger :: proc(q: ^Formula, pats: ..^Formula) {
    if q == nil || q.kind != .Quant do return
    t := make([dynamic]^Formula, 0, len(pats))
    for p in pats do append(&t, p)
    append(&q.triggers, t)
}

f_let :: proc(bindings: [dynamic]Let_Binding, body: ^Formula) -> ^Formula {
    f := new(Formula)
    f.kind = .Let
    f.let_bindings = bindings
    f.body = body
    f.sort = body.sort
    return f
}

// ---------- Declarations (for decl-fun emission) ----------
// The SMT-LIB2 script needs (declare-fun name (args) ret) before usage.
// We collect declarations while building ; emit phase emits them in sorted order.

Decl :: struct {
    name:     string,
    arg_sorts: [dynamic]^Sort,
    ret:      ^Sort,
    is_const: bool,   // zero-arg constant
}

// ---------- Script : a list of assertions + declarations + options ----------

Smt_Script :: struct {
    logic:    Theory,
    options:  map[string]string,    // (set-option :key val)
    decls:    map[string]Decl,      // name → Decl  (sorted on emit)
    sort_decls: [dynamic]string,    // names of declare-sort'd symbols
    asserts:  [dynamic]^Formula,
    produce_models: bool,
    produce_unsat_cores: bool,
    get_model:       bool,
    timeout_ms:      int,
}

new_script :: proc(logic: Theory = .ALL) -> ^Smt_Script {
    s := new(Smt_Script)
    s.logic   = logic
    s.options = make(map[string]string)
    s.decls   = make(map[string]Decl)
    s.sort_decls = make([dynamic]string)
    s.asserts = make([dynamic]^Formula)
    s.produce_models = true
    s.produce_unsat_cores = false
    s.get_model = false
    s.timeout_ms = 10_000
    return s
}

script_destroy :: proc(s: ^Smt_Script) {
    if s == nil do return
    delete(s.options)
    for _, d in s.decls do delete(d.arg_sorts)
    delete(s.decls)
    delete(s.sort_decls)
    delete(s.asserts)
}

script_set_option :: proc(s: ^Smt_Script, key, val: string) {
    s.options[strings.clone(key)] = strings.clone(val)
}

script_declare_const :: proc(s: ^Smt_Script, name: string, sort: ^Sort) {
    if _, found := s.decls[name]; found do return
    d: Decl
    d.name = strings.clone(name)
    d.ret  = sort
    d.is_const = true
    d.arg_sorts = make([dynamic]^Sort)
    s.decls[d.name] = d
}

script_declare_fun :: proc(s: ^Smt_Script, name: string, arg_sorts: [dynamic]^Sort, ret: ^Sort) {
    if _, found := s.decls[name]; found do return
    d: Decl
    d.name = strings.clone(name)
    d.ret  = ret
    d.is_const = len(arg_sorts) == 0
    d.arg_sorts = arg_sorts
    s.decls[d.name] = d
}

script_declare_sort :: proc(s: ^Smt_Script, name: string) {
    for existing in s.sort_decls do if existing == name do return
    append(&s.sort_decls, strings.clone(name))
}

script_assert :: proc(s: ^Smt_Script, f: ^Formula) {
    append(&s.asserts, f)
}

// ---------- Free-variable collection (auto-fills declarations) ----------
// Walk a formula, discover Var references whose name is not already declared,
// and add (declare-const name sort) entries to the script automatically.

script_autodecl_from_formula :: proc(s: ^Smt_Script, f: ^Formula) {
    if f == nil do return
    bound: map[string]bool
    defer delete(bound)
    autodecl_walk(s, f, &bound)
}

@(private="file")
autodecl_walk :: proc(s: ^Smt_Script, f: ^Formula, bound: ^map[string]bool) {
    if f == nil do return
    #partial switch f.kind {
    case .Var:
        if bound[f.name] do return
        if _, have := s.decls[f.name]; have do return
        script_declare_const(s, f.name, f.sort)
    case .Apply:
        for a in f.args do autodecl_walk(s, a, bound)
    case .Ite:
        autodecl_walk(s, f.cond, bound)
        autodecl_walk(s, f.th, bound)
        autodecl_walk(s, f.el, bound)
    case .Let:
        // let bindings are defined-in-order ; rhs may reference earlier bindings
        local_bound: map[string]bool
        for k, v in bound do local_bound[k] = v
        for lb in f.let_bindings {
            autodecl_walk(s, lb.expr, &local_bound)
            local_bound[lb.name] = true
        }
        autodecl_walk(s, f.body, &local_bound)
        delete(local_bound)
    case .Quant:
        local_bound: map[string]bool
        for k, v in bound do local_bound[k] = v
        for b in f.quant_vars do local_bound[b.name] = true
        autodecl_walk(s, f.body, &local_bound)
        for t in f.triggers {
            for p in t do autodecl_walk(s, p, &local_bound)
        }
        delete(local_bound)
    }
}

// ---------- Formula pretty-print (for diagnostics) ----------

formula_repr :: proc(f: ^Formula) -> string {
    sb := strings.builder_make()
    formula_repr_into(&sb, f)
    return strings.to_string(sb)
}

formula_repr_into :: proc(sb: ^strings.Builder, f: ^Formula) {
    if f == nil {
        strings.write_string(sb, "<nil>")
        return
    }
    switch f.kind {
    case .Var:
        strings.write_string(sb, f.name)
    case .BoolC:
        strings.write_string(sb, f.b_val ? "true" : "false")
    case .IntC:
        strings.write_string(sb, fmt.tprintf("%d", f.i_val))
    case .RealC:
        if f.r_den == 1 do strings.write_string(sb, fmt.tprintf("%d.0", f.r_num))
        else do strings.write_string(sb, fmt.tprintf("(/ %d %d)", f.r_num, f.r_den))
    case .BvC:
        strings.write_string(sb, fmt.tprintf("(_ bv%d %d)", f.i_val, f.bv_width))
    case .Apply:
        if len(f.args) == 0 {
            strings.write_string(sb, f.op)
        } else {
            strings.write_byte(sb, '(')
            strings.write_string(sb, f.op)
            for a in f.args {
                strings.write_byte(sb, ' ')
                formula_repr_into(sb, a)
            }
            strings.write_byte(sb, ')')
        }
    case .Ite:
        strings.write_string(sb, "(ite ")
        formula_repr_into(sb, f.cond) ; strings.write_byte(sb, ' ')
        formula_repr_into(sb, f.th)   ; strings.write_byte(sb, ' ')
        formula_repr_into(sb, f.el)   ; strings.write_byte(sb, ')')
    case .Let:
        strings.write_string(sb, "(let (")
        for lb, i in f.let_bindings {
            if i > 0 do strings.write_byte(sb, ' ')
            strings.write_string(sb, fmt.tprintf("(%s ", lb.name))
            formula_repr_into(sb, lb.expr)
            strings.write_byte(sb, ')')
        }
        strings.write_string(sb, ") ")
        formula_repr_into(sb, f.body)
        strings.write_byte(sb, ')')
    case .Quant:
        strings.write_byte(sb, '(')
        strings.write_string(sb, f.quant_kind == .Forall ? "forall" : "exists")
        strings.write_string(sb, " (")
        for b, i in f.quant_vars {
            if i > 0 do strings.write_byte(sb, ' ')
            strings.write_string(sb, fmt.tprintf("(%s %s)", b.name, sort_repr(b.sort)))
        }
        strings.write_string(sb, ") ")
        formula_repr_into(sb, f.body)
        for t in f.triggers {
            strings.write_string(sb, " :pattern (")
            for p, i in t {
                if i > 0 do strings.write_byte(sb, ' ')
                formula_repr_into(sb, p)
            }
            strings.write_byte(sb, ')')
        }
        strings.write_byte(sb, ')')
    }
}

// ---------- Theory auto-inference ----------
// Given a script, infer the tightest SMT logic that covers its operators.

infer_theory :: proc(s: ^Smt_Script) -> Theory {
    has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf := false, false, false, false, false, false, false
    for a in s.asserts {
        infer_walk(a, &has_int, &has_real, &has_nl, &has_bv, &has_array, &has_quant, &has_uf)
    }
    for _, d in s.decls {
        if len(d.arg_sorts) > 0 do has_uf = true
        if d.ret != nil {
            if d.ret.kind == .Array do has_array = true
            if d.ret.kind == .Int   do has_int = true
            if d.ret.kind == .Real  do has_real = true
            if d.ret.kind == .BitVec do has_bv = true
        }
        for as in d.arg_sorts {
            if as.kind == .Array do has_array = true
            if as.kind == .Int   do has_int = true
            if as.kind == .Real  do has_real = true
            if as.kind == .BitVec do has_bv = true
        }
    }
    if has_quant do return has_real ? .AUFLIRA : .AUFLIA
    if has_array do return .AUFLIA
    if has_bv    do return .QF_BV
    if has_nl && has_real do return .QF_NRA
    if has_nl && has_int  do return .QF_NIA
    if has_uf && has_real do return .QF_UFLRA
    if has_uf && has_int  do return .QF_UFLIA
    if has_real  do return .QF_LRA
    if has_int   do return .QF_LIA
    if has_uf    do return .QF_UF
    return .ALL
}

@(private="file")
infer_walk :: proc(f: ^Formula, has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf: ^bool) {
    if f == nil do return
    if f.sort != nil {
        #partial switch f.sort.kind {
        case .Int:    has_int^    = true
        case .Real:   has_real^   = true
        case .BitVec: has_bv^     = true
        case .Array:  has_array^  = true
        }
    }
    #partial switch f.kind {
    case .Apply:
        // multiplication/mod/div with two non-const args ⇒ non-linear
        if (f.op == "*" || f.op == "div" || f.op == "mod") && len(f.args) == 2 {
            l := f.args[0] ; r := f.args[1]
            if l != nil && r != nil && l.kind != .IntC && l.kind != .RealC &&
               r.kind != .IntC && r.kind != .RealC {
                has_nl^ = true
            }
        }
        // "select"/"store" ⇒ arrays
        if f.op == "select" || f.op == "store" do has_array^ = true
        // heuristic: user-defined op names (non-SMT-LIB2-builtin) ⇒ UF
        if !is_builtin_op(f.op) do has_uf^ = true
        for a in f.args {
            infer_walk(a, has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf)
        }
    case .Ite:
        infer_walk(f.cond, has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf)
        infer_walk(f.th,   has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf)
        infer_walk(f.el,   has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf)
    case .Quant:
        has_quant^ = true
        infer_walk(f.body, has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf)
        for t in f.triggers {
            for p in t do infer_walk(p, has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf)
        }
    case .Let:
        for lb in f.let_bindings {
            infer_walk(lb.expr, has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf)
        }
        infer_walk(f.body, has_int, has_real, has_nl, has_bv, has_array, has_quant, has_uf)
    }
}

@(private="file")
is_builtin_op :: proc(op: string) -> bool {
    switch op {
    case "and","or","not","=>","=","distinct","ite",
         "<","<=",">",">=",
         "+","-","*","/","div","mod","abs",
         "select","store",
         "bvadd","bvsub","bvmul","bvudiv","bvurem","bvand","bvor","bvxor","bvnot",
         "bvshl","bvlshr","bvashr","bvult","bvule","bvugt","bvuge","bvslt","bvsle",
         "concat","extract":
        return true
    }
    return false
}
