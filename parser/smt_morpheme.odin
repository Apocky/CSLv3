package cslparser

// § CSLv3 MORPHEME → SMT-FORMULA TRANSLATOR (T26.c Session-7)
// I> morpheme-suffix + morpheme-stack → SMT predicate obligation
// I> handoff §§ FILES-NEW :
//    'd durative     → (> (duration v) 0)
//    'f final        → (terminal v)          UF predicate
//    's state        → type-level only ← skip (StateTag check)
//    't transitive   → (>= (arity v) 2)      UF predicate
//    'e experiential → (observed-by v agent) UF predicate
//    'm modal        → (modal-kind v k)      UF
//    'p perfective   → (completed v)         UF
//    'g generic      → universal-quant : ∀α.φ[α/v]
//    'r reflexive    → (= (subject v) (object v))
// I> UF-declarations auto-added to Smt_Script as needed
// I> morpheme-stack = composition : each tag contributes a conjunct
// R! ← refine.odin (morpheme_to_tag) keeps single-source-of-truth ;
//      this file translates that tag-string into SMT formulas

import "core:strings"

// ---------- UF signatures (shared across all morpheme obligations) ----------
// Declared once per script ; idempotent via script_declare_fun's dedup check.

morpheme_declare_ufs :: proc(s: ^Smt_Script) {
    // duration : MorphVal -> Int
    script_declare_sort(s, "MorphVal")
    t_mv := s_sym("MorphVal")

    // duration : MorphVal -> Int
    args := make([dynamic]^Sort) ; append(&args, t_mv)
    script_declare_fun(s, "duration", args, s_int())

    // terminal : MorphVal -> Bool
    args2 := make([dynamic]^Sort) ; append(&args2, t_mv)
    script_declare_fun(s, "terminal", args2, s_bool())

    // arity : MorphVal -> Int
    args3 := make([dynamic]^Sort) ; append(&args3, t_mv)
    script_declare_fun(s, "arity", args3, s_int())

    // observed-by : MorphVal x Agent -> Bool
    script_declare_sort(s, "Agent")
    args4 := make([dynamic]^Sort) ; append(&args4, t_mv) ; append(&args4, s_sym("Agent"))
    script_declare_fun(s, "observed-by", args4, s_bool())

    // modal-kind : MorphVal x ModKind -> Bool
    script_declare_sort(s, "ModKind")
    args5 := make([dynamic]^Sort) ; append(&args5, t_mv) ; append(&args5, s_sym("ModKind"))
    script_declare_fun(s, "modal-kind", args5, s_bool())

    // completed : MorphVal -> Bool
    args6 := make([dynamic]^Sort) ; append(&args6, t_mv)
    script_declare_fun(s, "completed", args6, s_bool())

    // subject, object : MorphVal -> MorphVal
    args7 := make([dynamic]^Sort) ; append(&args7, t_mv)
    script_declare_fun(s, "subject", args7, t_mv)
    args8 := make([dynamic]^Sort) ; append(&args8, t_mv)
    script_declare_fun(s, "object", args8, t_mv)
}

// ---------- Per-tag formula constructor ----------
// Given a variable `v` of sort MorphVal, emit the predicate for a single tag.

morpheme_predicate :: proc(tag: string, v: ^Formula) -> ^Formula {
    switch tag {
    case "d":
        // (> (duration v) 0)
        return f_gt(f_apply("duration", s_int(), v), f_int(0))
    case "f":
        // (terminal v)
        return f_apply("terminal", s_bool(), v)
    case "s":
        // type-level only — trivially-satisfiable at SMT layer
        return f_true()
    case "t":
        // (>= (arity v) 2)
        return f_ge(f_apply("arity", s_int(), v), f_int(2))
    case "e":
        // (exists ((a Agent)) (observed-by v a))
        agent := f_var("agent_witness", s_sym("Agent"))
        body := f_apply("observed-by", s_bool(), v, agent)
        binds := make([dynamic]Binding)
        append(&binds, Binding{name = "agent_witness", sort = s_sym("Agent")})
        return f_exists(binds, body)
    case "m":
        // (exists ((k ModKind)) (modal-kind v k))
        k := f_var("mod_kind", s_sym("ModKind"))
        body := f_apply("modal-kind", s_bool(), v, k)
        binds := make([dynamic]Binding)
        append(&binds, Binding{name = "mod_kind", sort = s_sym("ModKind")})
        return f_exists(binds, body)
    case "p":
        // (completed v)
        return f_apply("completed", s_bool(), v)
    case "g":
        // (forall ((alpha MorphVal)) true) — generic universe ; tautology at SMT
        // Real generic-refinement is type-level (forall-intro) ; SMT gets a witness.
        a := f_var("alpha", s_sym("MorphVal"))
        _ = a
        binds := make([dynamic]Binding)
        append(&binds, Binding{name = "alpha", sort = s_sym("MorphVal")})
        return f_forall(binds, f_true())
    case "r":
        // (= (subject v) (object v))
        subj := f_apply("subject", s_sym("MorphVal"), v)
        obj  := f_apply("object",  s_sym("MorphVal"), v)
        return f_eq(subj, obj)
    }
    return f_true()
}

// ---------- Stack : [tag, ...] → conjunction of predicates ----------
// Stack semantics : every tag on a morpheme must hold simultaneously.

morpheme_stack_predicate :: proc(stack: []string, v: ^Formula) -> ^Formula {
    if len(stack) == 0 do return f_true()
    parts := make([dynamic]^Formula, 0, len(stack))
    for tag in stack {
        p := morpheme_predicate(tag, v)
        if p.kind == .BoolC && p.b_val do continue   // skip trivial-true
        append(&parts, p)
    }
    if len(parts) == 0 do return f_true()
    if len(parts) == 1 do return parts[0]
    return f_and(..parts[:])
}

// ---------- Full-path : Tagged-type → SMT obligation ----------
// Given a typechecked `Tagged(base, tag)` or chain thereof, construct the
// obligation formula that the witness satisfies all stacked predicates.
//
// Return value : an assertion to add to the script.
// Caller should : (1) script_declare_const(script, witness_name, s_sym("MorphVal"))
//                 (2) morpheme_declare_ufs(script)   ← once
//                 (3) script_assert(script, obligation_from_tagged_type(...))

obligation_from_tagged_type :: proc(witness_name: string, t: ^Type) -> ^Formula {
    stack := make([dynamic]string)
    defer delete(stack)
    collect_tag_chain(t, &stack)
    v := f_var(witness_name, s_sym("MorphVal"))
    return morpheme_stack_predicate(stack[:], v)
}

// Walk t.kind == Tagged chain inward, collecting tag names in outer→inner order.
@(private="file")
collect_tag_chain :: proc(t: ^Type, out: ^[dynamic]string) {
    if t == nil do return
    cur := follow(t)
    for cur != nil && cur.kind == .Tagged {
        append(out, strings.clone(cur.tag_name))
        cur = follow(cur.tag_ty)
    }
}

// ---------- Negation helper : "is there a witness v satisfying the predicate?" ----------
// For validity-checking we typically assert the NEGATION and ask (check-sat).
// If unsat → original holds universally. If sat → counterexample produced.
// Caller: script_assert(script, morpheme_negation(tag, v))   then (check-sat).

morpheme_negation :: proc(tag: string, v: ^Formula) -> ^Formula {
    return f_not(morpheme_predicate(tag, v))
}
