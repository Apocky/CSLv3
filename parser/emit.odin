package cslparser

// § CSLv3 EMIT FRAMEWORK (T28.a Session-10)
// I> target-agnostic emit-framework ; 5 backends (MIR/Markdown/HTML/LaTeX/JSON)
// I> visitor-pattern dispatch ; matches pprint + ir_print precedent
// I> deterministic-output contract : byte-stable across-runs
// I> cert-signing hook via smt_audit Ed25519 reusable infra
// I> source-map threading per-target ; sidecar .map file default
// I> incremental-emit via emit_cache BLAKE3(source+target+config) key
// R! ← MLIR-printer + pandoc-writers + Sphinx architecture-lineage

import "core:fmt"
import "core:strings"

// ---------- Target selection ----------

Emit_Target :: enum {
    MIR,
    Markdown,
    HTML,
    LaTeX,
    JSON,
}

emit_target_name :: proc(t: Emit_Target) -> string {
    switch t {
    case .MIR:      return "mir"
    case .Markdown: return "markdown"
    case .HTML:     return "html"
    case .LaTeX:    return "latex"
    case .JSON:     return "json"
    }
    return "?"
}

emit_target_parse :: proc(s: string) -> (Emit_Target, bool) {
    switch s {
    case "mir", "cssl-mir", "cssl":     return .MIR,      true
    case "md", "markdown", "gfm":        return .Markdown, true
    case "html", "html5":                return .HTML,     true
    case "tex", "latex":                 return .LaTeX,    true
    case "json":                          return .JSON,     true
    }
    return .JSON, false
}

emit_target_extension :: proc(t: Emit_Target) -> string {
    switch t {
    case .MIR:      return "mir"
    case .Markdown: return "md"
    case .HTML:     return "html"
    case .LaTeX:    return "tex"
    case .JSON:     return "json"
    }
    return "txt"
}

// ---------- Emit configuration ----------

Emit_Config :: struct {
    source_map:    bool,   // emit source-map (.map sidecar or inline)
    sign:          bool,   // sign output via Ed25519 audit-chain
    incremental:   bool,   // consult cache / skip-re-emit on hash-match
    standalone:    bool,   // (HTML/LaTeX) full-document vs fragment
    schema_print:  bool,   // --schema : print target schema and exit
    strict:        bool,   // fail on warnings (missing source-map etc.)
    out_path:      string, // "" = stdout
}

emit_config_default :: proc() -> Emit_Config {
    return Emit_Config{
        source_map  = true,
        sign        = false,
        incremental = false,
        standalone  = true,
        schema_print= false,
        strict      = false,
        out_path    = "",
    }
}

// ---------- Emit context ----------
// All three IR-levels are carried so each target picks its preferred source :
//   MIR      : walks ir_module (post-lowering)
//   Markdown : walks ast_root  (pre-typecheck)
//   HTML     : walks ast_root  + type annotations
//   LaTeX    : walks ast_root  + type annotations
//   JSON     : walks ir_module + ast_root + tc_result (unified superset)

Emit_Context :: struct {
    source_file:  string,
    source_text:  string,
    ast_root:     ^Node,
    tc_result:    ^Tc_Result,
    ir_module:    ^Module,
    target:       Emit_Target,
    config:       Emit_Config,
    // per-emission stats
    bytes_written: int,
    nodes_visited: int,
    elapsed_ms:    int,
    warnings:      [dynamic]string,
}

emit_context_init :: proc(ctx: ^Emit_Context, t: Emit_Target) {
    ctx.target = t
    ctx.config = emit_config_default()
    ctx.warnings = make([dynamic]string)
}

emit_context_destroy :: proc(ctx: ^Emit_Context) {
    for w in ctx.warnings do delete(w)
    delete(ctx.warnings)
}

emit_warn :: proc(ctx: ^Emit_Context, msg: string) {
    append(&ctx.warnings, strings.clone(msg))
}

// ---------- Public entry ----------

Emit_Result :: struct {
    bytes:         string,
    source_map:    string,   // v3 sourcemap JSON (empty if disabled)
    cert:          string,   // Ed25519 signature hex (empty if unsigned)
    target:        Emit_Target,
    cached:        bool,
    elapsed_ms:    int,
    warnings:      []string,
    schema_version: string,
}

emit :: proc(ctx: ^Emit_Context) -> Emit_Result {
    start := time_now_ms()
    r: Emit_Result
    r.target = ctx.target

    // incremental-cache lookup
    if ctx.config.incremental {
        key := emit_cache_key(ctx)
        if cached, found := emit_cache_lookup(key); found {
            r.bytes = cached.bytes
            r.source_map = cached.source_map
            r.cert = cached.cert
            r.cached = true
            r.schema_version = cached.schema_version
            r.elapsed_ms = 0
            return r
        }
    }

    // target dispatch
    switch ctx.target {
    case .MIR:      r.bytes = emit_mir(ctx)
    case .Markdown: r.bytes = emit_markdown(ctx)
    case .HTML:     r.bytes = emit_html(ctx)
    case .LaTeX:    r.bytes = emit_latex(ctx)
    case .JSON:     r.bytes = emit_json_target(ctx)
    }

    r.schema_version = schema_version_for(ctx.target)

    if ctx.config.source_map {
        r.source_map = build_source_map(ctx)
    }

    if ctx.config.sign {
        r.cert = emit_sign(ctx, r.bytes)
    }

    ctx.bytes_written = len(r.bytes)
    r.elapsed_ms = time_now_ms() - start
    ctx.elapsed_ms = r.elapsed_ms

    // Collect warnings as a leak-free slice.
    r.warnings = make([]string, len(ctx.warnings))
    for w, i in ctx.warnings do r.warnings[i] = w

    // incremental-cache store
    if ctx.config.incremental {
        key := emit_cache_key(ctx)
        emit_cache_store(key, Emit_Cache_Entry{
            bytes          = r.bytes,
            source_map     = r.source_map,
            cert           = r.cert,
            target         = ctx.target,
            schema_version = r.schema_version,
            created_ms     = time_now_ms(),
        })
    }

    return r
}

// ---------- Schema versioning ----------

schema_version_for :: proc(t: Emit_Target) -> string {
    switch t {
    case .MIR:      return "mir-v1"
    case .Markdown: return "markdown-v1"
    case .HTML:     return "html-v1"
    case .LaTeX:    return "latex-v1"
    case .JSON:     return "json-v1"
    }
    return "v?"
}

schema_text_for :: proc(t: Emit_Target) -> string {
    switch t {
    case .MIR:      return MIR_SCHEMA_TEXT
    case .Markdown: return MARKDOWN_STYLE_TEXT
    case .HTML:     return HTML_CSS_TEXT
    case .LaTeX:    return LATEX_STY_TEXT
    case .JSON:     return JSON_SCHEMA_TEXT
    }
    return ""
}

// ---------- Cert-signing ----------
// Reuses the smt_audit Ed25519 keypair at .proof/keys/. Proof-dir init
// is idempotent + creates a dev-stub key on first use.

@(private="file")
emit_sign :: proc(ctx: ^Emit_Context, body: string) -> string {
    proof_dir := ".proof"
    if !audit_init(proof_dir) {
        emit_warn(ctx, "cert-sign: audit-init failed")
        return ""
    }
    // Canonical content for signing = target|schema|hash(body)
    canonical := fmt.tprintf("%s|%s|%s",
        emit_target_name(ctx.target),
        schema_version_for(ctx.target),
        sha256_hex_of_string(body))
    // Create a synthetic Obligation-shaped record so audit_append accepts it.
    o: Obligation
    o.kind = .Refinement_Assert   // reuse-slot ; audit doesn't interpret kind
    o.mode = .Consistency
    o.source = Source_Pos{}
    o.context_ = fmt.tprintf("emit:%s:%s", emit_target_name(ctx.target), ctx.source_file)
    o.result = .Unsat   // stand-in for "emitted successfully"
    o.solver_used = "emit-cert"
    o.cert_hash = canonical
    if !audit_append(proof_dir, &o) {
        emit_warn(ctx, "cert-sign: audit-append failed")
        return ""
    }
    // return canonical as cert reference (full sig is inside audit chain)
    return canonical
}

// ---------- Source-map (v3 sidecar format) ----------
// Minimal skeleton : we emit mapping-bytes = empty mappings string for
// cases where the backend hasn't populated per-segment maps. Targets that
// track segments populate via emit_source_map_record.

@(private="file")
build_source_map :: proc(ctx: ^Emit_Context) -> string {
    return source_map_v3(ctx)
}

// ---------- Self-test hook ----------

emit_selftest_main :: proc() {
    total := 0
    pass  := 0
    targets := [?]Emit_Target{.JSON, .Markdown, .HTML, .LaTeX, .MIR}

    for t in targets {
        total += 1
        sample := "§ T\n  hp : i32\n"
        doc, _, _ := parse_source(sample, "<selftest>")
        tc := typecheck(doc, .Default, false)
        defer tc_result_destroy(&tc)
        lowered := lower_source(doc, &tc, "<selftest>")

        ctx: Emit_Context
        emit_context_init(&ctx, t)
        defer emit_context_destroy(&ctx)
        ctx.source_file = "<selftest>"
        ctx.source_text = sample
        ctx.ast_root    = doc
        ctx.tc_result   = &tc
        ctx.ir_module   = lowered.module

        r := emit(&ctx)
        if len(r.bytes) > 0 && len(r.schema_version) > 0 {
            fmt.printf("CASE %d: PASS emit-%s (%d bytes)\n",
                total, emit_target_name(t), len(r.bytes))
            pass += 1
        } else {
            fmt.printf("CASE %d: FAIL emit-%s (empty output)\n",
                total, emit_target_name(t))
        }
    }
    fmt.printf("EMIT-SELFTEST: %d/%d PASS\n", pass, total)
}
