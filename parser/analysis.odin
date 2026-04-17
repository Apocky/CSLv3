package cslparser

// § CSLv3 IR ANALYSIS PASSES (T27.b Session-8)
// I> use-def chains : per-Value track its defining Op + all uses
// I> dominance : structured-CFG is already-tree-shaped ; regions → blocks →
//                 nested-ops ⇒ dominance = lexical-scope nesting
// I> alias / escape : stub analyses returning conservative-info
//                     (future-expansion ; Session-9+ ready)
// R! ← Cytron et al. 1991 for SSA-dominance ; our structured IR makes this
//      O(n) walk instead of iterated-dominance-frontiers.

import "core:fmt"
import "core:strings"

// ---------- Use-Def chains ----------

Use_Site :: struct {
    op:   ^Op,
    idx:  int,   // index within op.operands
}

Use_Def :: struct {
    defs: map[^Value]^Op,            // Value → defining Op (nil for block-args)
    uses: map[^Value][dynamic]Use_Site,
    n_ops: int,
    n_values: int,
}

usedef_build :: proc(m: ^Module) -> ^Use_Def {
    ud := new(Use_Def)
    ud.defs = make(map[^Value]^Op)
    ud.uses = make(map[^Value][dynamic]Use_Site)

    if m == nil do return ud
    for op in m.ops do ud_walk_op(ud, op)
    return ud
}

usedef_destroy :: proc(ud: ^Use_Def) {
    if ud == nil do return
    delete(ud.defs)
    for _, v in ud.uses do delete(v)
    delete(ud.uses)
    free(ud)
}

@(private="file")
ud_walk_op :: proc(ud: ^Use_Def, op: ^Op) {
    if op == nil do return
    ud.n_ops += 1
    for r in op.results {
        if r != nil {
            ud.defs[r] = op
            ud.n_values += 1
        }
    }
    for operand, i in op.operands {
        if operand == nil do continue
        v, found := ud.uses[operand]
        if !found {
            v = make([dynamic]Use_Site)
        }
        append(&v, Use_Site{op = op, idx = i})
        ud.uses[operand] = v
    }
    for region in op.regions {
        if region == nil do continue
        for b in region.blocks {
            if b == nil do continue
            for arg in b.args {
                if arg != nil do ud.n_values += 1
                // Block-arg defs are implicit ; we still record nil-def for
                // "is-this-defined-somewhere" queries.
                ud.defs[arg] = nil
            }
            for child in b.ops do ud_walk_op(ud, child)
        }
    }
}

// Uses of a value ; empty slice if no uses tracked.
usedef_uses :: proc(ud: ^Use_Def, v: ^Value) -> []Use_Site {
    if ud == nil do return nil
    if uses, ok := ud.uses[v]; ok do return uses[:]
    return nil
}

// Number of uses.
usedef_use_count :: proc(ud: ^Use_Def, v: ^Value) -> int {
    if ud == nil do return 0
    if uses, ok := ud.uses[v]; ok do return len(uses)
    return 0
}

// True iff `v` has no recorded uses (safe-to-delete candidate).
usedef_is_dead :: proc(ud: ^Use_Def, v: ^Value) -> bool {
    return usedef_use_count(ud, v) == 0
}

// ---------- Dominance (structured-CFG tree) ----------
// In our structured IR an Op is inside exactly one enclosing Block (or nil
// at module-root). A Block is inside exactly one enclosing Region. A Region
// is inside exactly one enclosing Op. This is a tree. So dominance is just
// "is ancestor in that tree". We don't materialize a DomTree struct —
// `dominates(a, b)` is a direct pointer-chase up the parent chain.

// True iff Op `a` dominates Op `b` — i.e. `a`'s Block is on the path from
// `b` up to the module root AND `a` precedes `b` in `a`'s Block.
op_dominates :: proc(a, b: ^Op) -> bool {
    if a == nil || b == nil do return false
    if a == b do return true
    // Walk up from b's block through parent regions/ops until we hit a's block
    cur := b
    for cur != nil {
        pblk := cur.parent
        if pblk == nil do return false
        if pblk == a.parent {
            // Both in same block : compare positional order within block
            return block_position(a) < block_position(cur)
        }
        // Step up : from pblk → enclosing Region → enclosing Op
        if pblk.parent == nil do return false
        cur = pblk.parent.parent_op
    }
    return false
}

@(private="file")
block_position :: proc(op: ^Op) -> int {
    if op == nil || op.parent == nil do return -1
    for o, i in op.parent.ops {
        if o == op do return i
    }
    return -1
}

// ---------- Alias analysis (conservative stub) ----------

Alias_Info :: struct {
    // For now, a flat table : Value → "may-alias" set of other Values.
    // Empty = conservative (may-alias-everything) in the base implementation.
    may_alias: map[^Value][dynamic]^Value,
}

alias_build :: proc(m: ^Module) -> ^Alias_Info {
    ai := new(Alias_Info)
    ai.may_alias = make(map[^Value][dynamic]^Value)
    return ai   // empty ⇒ conservative : assume any two ptrs may alias
}

alias_destroy :: proc(a: ^Alias_Info) {
    if a == nil do return
    for _, v in a.may_alias do delete(v)
    delete(a.may_alias)
    free(a)
}

// Conservative query — returns true by default.
alias_may_alias :: proc(ai: ^Alias_Info, x, y: ^Value) -> bool {
    if ai == nil || x == y do return true
    // If we've proven disjointness, return false ; else conservatively true.
    // Current base impl has no disjointness info.
    return true
}

// ---------- Escape analysis (stub) ----------

Escape_Info :: struct {
    escapes: map[^Value]bool,
}

escape_build :: proc(m: ^Module) -> ^Escape_Info {
    ei := new(Escape_Info)
    ei.escapes = make(map[^Value]bool)
    return ei   // empty map ⇒ nothing-proven-non-escaping
}

escape_destroy :: proc(e: ^Escape_Info) {
    if e == nil do return
    delete(e.escapes)
    free(e)
}

escape_escapes :: proc(ei: ^Escape_Info, v: ^Value) -> bool {
    if ei == nil do return true
    return ei.escapes[v] || true   // conservative : every value escapes
}

// ---------- Analysis Pass wrappers ----------

make_pass_analysis_usedef :: proc() -> Pass {
    return Pass{
        name = "usedef",
        kind = .Analysis,
        run  = usedef_pass_run,
    }
}

usedef_pass_run :: proc(ctx: ^Pass_Ctx, m: ^Module) -> Pass_Stats {
    // Clean up previous if any
    if prev, ok := ctx.analyses["usedef"]; ok {
        usedef_destroy((^Use_Def)(prev))
    }
    ud := usedef_build(m)
    ctx.analyses["usedef"] = rawptr(ud)
    st: Pass_Stats
    st.ran = 1
    st.note = fmt.tprintf("ops=%d values=%d", ud.n_ops, ud.n_values)
    return st
}

// Convenience : retrieve cached use-def from ctx ; build-on-demand if absent.
get_usedef :: proc(ctx: ^Pass_Ctx, m: ^Module) -> ^Use_Def {
    if prev, ok := ctx.analyses["usedef"]; ok do return (^Use_Def)(prev)
    ud := usedef_build(m)
    ctx.analyses["usedef"] = rawptr(ud)
    ctx.live_analyses["usedef"] = true
    return ud
}

// ---------- Helper : drain all use-def dynamic arrays (debug) ----------
usedef_print :: proc(ud: ^Use_Def) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, fmt.tprintf("use-def : %d ops / %d values\n",
                                           ud.n_ops, ud.n_values))
    for v, sites in ud.uses {
        strings.write_string(&sb, fmt.tprintf("  %%%d → %d uses\n", v.id, len(sites)))
    }
    return strings.to_string(sb)
}
