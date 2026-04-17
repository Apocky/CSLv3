package cslparser

// § CSLv3 TYPE-CHECKER — REFINEMENT via MORPHEME-SUFFIX (T20.c Session-5)
// I> type-suffix glyph ('d 'f 's 't 'e 'm 'p 'g 'r) produces refinement tag
// I> refinement-obligation queue — SMT-discharged in T26 (deferred)
// I> morpheme composition : Tagged(base, chain) for multi-suffix stacks
// W! canonical φ-templates per handoff Q20 map

import "core:fmt"

// ---------- Morpheme-to-refinement map (handoff T20 table) ----------

morpheme_to_tag :: proc(suffix: Token_Kind) -> string {
    #partial switch suffix {
    case .Suffix_Data:     return "d"  // durative  — {v | duration(v) > 0}
    case .Suffix_Func:     return "f"  // final     — {v | terminal(v)}
    case .Suffix_System:   return "s"  // state     — StateTag<ref τ>
    case .Suffix_Type:     return "t"  // transitive — Arrow arity≥2
    case .Suffix_Entity:   return "e"  // experiential — ObservedBy<agent>
    case .Suffix_Material: return "m"  // modal     — Modal<kind>
    case .Suffix_Prop:     return "p"  // perfective — Completed<τ>
    case .Suffix_Gate:     return "g"  // generic   — ∀α.α
    case .Suffix_Rule:     return "r"  // reflexive — {v | subject(v)=object(v)}
    }
    return ""
}

morpheme_to_predicate :: proc(tag: string) -> string {
    switch tag {
    case "d": return "duration(v) > 0"
    case "f": return "terminal(v)"
    case "s": return "StateTag<ref>"
    case "t": return "Arrow arity>=2"
    case "e": return "ObservedBy<agent>"
    case "m": return "Modal<kind>"
    case "p": return "Completed<τ>"
    case "g": return "∀α.α"
    case "r": return "subject(v) = object(v)"
    }
    return ""
}

// ---------- Wrap a base type with a morpheme refinement ----------

wrap_with_suffix :: proc(base: ^Type, suffix: Token_Kind) -> ^Type {
    tag := morpheme_to_tag(suffix)
    if len(tag) == 0 do return base
    return t_tagged(base, tag)
}

// Wrap with morpheme-stack suffixes (from node.morphemes).
// Example : render.prog.cert  →  Tagged(base, "prog"), Tagged(_, "cert")
// Stacking order matches the morpheme-stack grammar aspect→mod→cert→scope.
wrap_with_morpheme_stack :: proc(base: ^Type, stack: [dynamic]string) -> ^Type {
    current := base
    for m in stack {
        current = t_tagged(current, m)
    }
    return current
}

// ---------- Refinement obligations ----------
// Collected during inference ; discharged in T26 (SMT queue).

Refine_Obligation :: struct {
    at_pos:   Source_Pos,
    base:     ^Type,
    pred:     string,
    context_: string,   // "assignment to X" / "call to f" / etc.
}

// Global queue — Session-5 stubs it ; T26 adds SMT solver.
@(private="file")
g_refine_queue: [dynamic]Refine_Obligation

refine_queue_init :: proc() {
    g_refine_queue = make([dynamic]Refine_Obligation)
}

refine_queue_destroy :: proc() {
    delete(g_refine_queue)
    g_refine_queue = nil
}

refine_queue_len :: proc() -> int { return len(g_refine_queue) }

refine_queue_add :: proc(o: Refine_Obligation) {
    append(&g_refine_queue, o)
}

refine_queue_snapshot :: proc() -> []Refine_Obligation {
    return g_refine_queue[:]
}

refine_queue_clear :: proc() {
    clear(&g_refine_queue)
}

// ---------- Detect obligation when unifying Tagged with non-Tagged ----------
// Usage : whenever the checker encounters T^tag where the concrete side lacks
// that tag, add a refinement obligation. Inference layer calls this.

emit_refine_obligation :: proc(at: Source_Pos, base: ^Type, tag_name: string, ctx_: string) {
    refine_queue_add(Refine_Obligation{
        at_pos   = at,
        base     = base,
        pred     = morpheme_to_predicate(tag_name),
        context_ = fmt.tprintf("%s : morpheme '%s' not discharged", ctx_, tag_name),
    })
}
