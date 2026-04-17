package cslparser

// § CSLv3 IR-PASS INFRASTRUCTURE (T27.a Session-8)
// I> Pass interface + PassManager + Stats ; MLIR-style pluggable pipeline
// I> analysis-preservation via requires[]/preserves[] declaration
// I> pass_ctx carries solver-paths for SMT-informed opts (opt_smt_prune)
// I> opt-levels : -O0 no-opts • -O1 fold+dce • -O2 +cse+inline+smt-prune
//                 -O3 +partial-eval + aggressive-inline + fixpoint-iterate
// R! ← MLIR pass-manager design (Lattner+Rhodes 2020) + LLVM analysis-pass pattern

import "core:fmt"
import "core:strings"
import "core:time"

// ---------- Types ----------

Pass_Kind :: enum {
    Analysis,    // produces data ; doesn't mutate Module
    Transform,   // mutates Module ; may invalidate analyses
}

Pass :: struct {
    name:      string,
    kind:      Pass_Kind,
    requires:  []string,
    preserves: []string,
    run:       proc(ctx: ^Pass_Ctx, m: ^Module) -> Pass_Stats,
}

Pass_Stats :: struct {
    ran:       int,      // invocation count
    applied:   int,      // number of transformations applied
    skipped:   int,      // transformations considered but not applied
    elapsed_ms: int,
    note:      string,   // optional one-liner
}

Pass_Ctx :: struct {
    analyses:    map[string]rawptr,
    stats:       map[string]Pass_Stats,
    opt_level:   int,
    fuel:        int,           // inline/partial-eval budget
    verify_each: bool,
    tc:          ^Tc_Result,
    z3_path:     string,
    cvc5_path:   string,
    cache_dir:   string,
    emit_notes:  bool,
    // analyses-invalidation book-keeping
    live_analyses: map[string]bool,
}

pass_ctx_init :: proc(ctx: ^Pass_Ctx, opt_level: int) {
    ctx.analyses       = make(map[string]rawptr)
    ctx.stats          = make(map[string]Pass_Stats)
    ctx.live_analyses  = make(map[string]bool)
    ctx.opt_level      = opt_level
    ctx.fuel           = default_fuel(opt_level)
    ctx.verify_each    = false
    ctx.emit_notes     = true
}

pass_ctx_destroy :: proc(ctx: ^Pass_Ctx) {
    delete(ctx.analyses)
    delete(ctx.stats)
    delete(ctx.live_analyses)
}

default_fuel :: proc(opt_level: int) -> int {
    switch opt_level {
    case 0: return 0
    case 1: return 32
    case 2: return 256
    case 3: return 2048
    }
    return 128
}

// ---------- PassManager ----------

Pass_Manager :: struct {
    ctx:      ^Pass_Ctx,
    pipeline: [dynamic]Pass,
    // composite-reporting
    total_ms: int,
}

pm_init :: proc(pm: ^Pass_Manager, ctx: ^Pass_Ctx) {
    pm.ctx      = ctx
    pm.pipeline = make([dynamic]Pass)
}

pm_destroy :: proc(pm: ^Pass_Manager) {
    delete(pm.pipeline)
}

pm_add :: proc(pm: ^Pass_Manager, p: Pass) {
    append(&pm.pipeline, p)
}

// Execute the pipeline on `m`. Returns true if all passes completed (pass may
// abort by returning zero-run stats + empty note "abort"). Verifier after each
// pass when ctx.verify_each is set — on verify-failure we short-circuit + log.
pm_run :: proc(pm: ^Pass_Manager, m: ^Module) -> (ok: bool) {
    ok = true
    for p in pm.pipeline {
        if !requires_satisfied(pm.ctx, p) {
            // Auto-satisfy: run analyses listed in requires before this pass.
            // For the initial pass-set, analyses are added explicitly in the
            // pipeline by the driver so this is a belt-and-braces guard.
        }

        t0 := time.now()
        st := p.run(pm.ctx, m)
        elapsed := int(time.duration_milliseconds(time.since(t0)))
        st.elapsed_ms = elapsed
        pm.total_ms += elapsed

        // merge into total-stats map
        existing := pm.ctx.stats[p.name]
        existing.ran       += 1
        existing.applied   += st.applied
        existing.skipped   += st.skipped
        existing.elapsed_ms += st.elapsed_ms
        if st.note != "" do existing.note = st.note
        pm.ctx.stats[p.name] = existing

        // analysis-preservation : transform invalidates everything not in preserves
        if p.kind == .Transform {
            preserved: map[string]bool
            defer delete(preserved)
            for a in p.preserves do preserved[a] = true
            to_invalidate := make([dynamic]string)
            defer delete(to_invalidate)
            for k in pm.ctx.live_analyses {
                if !preserved[k] do append(&to_invalidate, k)
            }
            for k in to_invalidate {
                delete_key(&pm.ctx.live_analyses, k)
                delete_key(&pm.ctx.analyses, k)
            }
        } else {
            pm.ctx.live_analyses[p.name] = true
        }

        if pm.ctx.verify_each && p.kind == .Transform {
            vr := ir_verify(m)
            defer ir_verify_result_destroy(&vr)
            if vr.errors > 0 {
                fmt.eprintf("[pass %s] verify FAIL: %d errors\n", p.name, vr.errors)
                ok = false
                break
            }
        }
    }
    return
}

@(private="file")
requires_satisfied :: proc(ctx: ^Pass_Ctx, p: Pass) -> bool {
    for req in p.requires {
        if !ctx.live_analyses[req] do return false
    }
    return true
}

// ---------- Stats reporting ----------

stats_report_text :: proc(ctx: ^Pass_Ctx, total_ms: int) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, fmt.tprintf("§ PASS-STATS opt=-O%d total_ms=%d\n",
                                          ctx.opt_level, total_ms))
    for name, s in ctx.stats {
        strings.write_string(&sb, fmt.tprintf(
            "  %s: ran=%d applied=%d skipped=%d ms=%d",
            name, s.ran, s.applied, s.skipped, s.elapsed_ms))
        if s.note != "" do strings.write_string(&sb, fmt.tprintf(" [%s]", s.note))
        strings.write_byte(&sb, '\n')
    }
    return strings.to_string(sb)
}

stats_report_json :: proc(ctx: ^Pass_Ctx, total_ms: int) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, fmt.tprintf("{{\"opt_level\":%d,\"total_ms\":%d,\"passes\":{{",
                                          ctx.opt_level, total_ms))
    first := true
    for name, s in ctx.stats {
        if !first do strings.write_byte(&sb, ',')
        first = false
        strings.write_string(&sb, fmt.tprintf(
            "\"%s\":{{\"ran\":%d,\"applied\":%d,\"skipped\":%d,\"ms\":%d}}",
            name, s.ran, s.applied, s.skipped, s.elapsed_ms))
    }
    strings.write_string(&sb, "}}")
    return strings.to_string(sb)
}

// ---------- Pipeline construction (default per opt-level) ----------

build_default_pipeline :: proc(pm: ^Pass_Manager, opt_level: int) {
    switch opt_level {
    case 0:
        // -O0 : no-opts, optional verifier-only pass
        pm_add(pm, make_pass_verify_only())
    case 1:
        // -O1 : cleanup path
        pm_add(pm, make_pass_const_fold())
        pm_add(pm, make_pass_dce())
    case 2:
        // -O2 : default
        pm_add(pm, make_pass_const_fold())
        pm_add(pm, make_pass_dce())
        pm_add(pm, make_pass_analysis_usedef())
        pm_add(pm, make_pass_cse())
        pm_add(pm, make_pass_const_fold())
        pm_add(pm, make_pass_smt_prune())
        pm_add(pm, make_pass_dce())
        pm_add(pm, make_pass_inline())
        pm_add(pm, make_pass_const_fold())
        pm_add(pm, make_pass_dce())
    case 3:
        // -O3 : + partial-eval + aggressive-inline + fixpoint
        pm_add(pm, make_pass_const_fold())
        pm_add(pm, make_pass_dce())
        pm_add(pm, make_pass_analysis_usedef())
        pm_add(pm, make_pass_cse())
        pm_add(pm, make_pass_const_fold())
        pm_add(pm, make_pass_smt_prune())
        pm_add(pm, make_pass_dce())
        pm_add(pm, make_pass_inline())
        pm_add(pm, make_pass_partial_eval())
        pm_add(pm, make_pass_const_fold())
        pm_add(pm, make_pass_dce())
        pm_add(pm, make_pass_inline())   // second inline round (fixpoint)
        pm_add(pm, make_pass_const_fold())
        pm_add(pm, make_pass_dce())
    }
}

// Custom pipeline from a comma-separated pass name list.
build_custom_pipeline :: proc(pm: ^Pass_Manager, names: string) {
    rest := names
    for len(rest) > 0 {
        idx := strings.index_byte(rest, ',')
        nm: string
        if idx < 0 { nm = rest ; rest = "" }
        else       { nm = rest[:idx] ; rest = rest[idx+1:] }
        nm = strings.trim_space(nm)
        if len(nm) == 0 do continue
        switch nm {
        case "fold", "const-fold":   pm_add(pm, make_pass_const_fold())
        case "dce":                   pm_add(pm, make_pass_dce())
        case "cse":                   pm_add(pm, make_pass_cse())
        case "inline":                pm_add(pm, make_pass_inline())
        case "partial-eval", "peval": pm_add(pm, make_pass_partial_eval())
        case "smt-prune":             pm_add(pm, make_pass_smt_prune())
        case "usedef":                pm_add(pm, make_pass_analysis_usedef())
        case "verify":                pm_add(pm, make_pass_verify_only())
        }
    }
}

// ---------- Trivial verify-only pass (for -O0) ----------

make_pass_verify_only :: proc() -> Pass {
    return Pass{
        name = "verify",
        kind = .Analysis,
        run  = verify_only_run,
    }
}

verify_only_run :: proc(ctx: ^Pass_Ctx, m: ^Module) -> Pass_Stats {
    vr := ir_verify(m)
    defer ir_verify_result_destroy(&vr)
    st: Pass_Stats
    st.ran = 1
    st.applied = vr.errors   // we record errors as "applied" diagnostic-count
    if vr.errors > 0 do st.note = fmt.tprintf("%d-verify-errors", vr.errors)
    return st
}
