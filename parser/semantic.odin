package cslparser

// § CSLv3 SEMANTIC ANALYZER  (T11 Session-3 + T14/T15 Session-4)
// I> post-parse pass : morphemes + aliases + scope + validity checks
// W! severity table (Q2 settled Session-3-close) :
//    dup-morph   = always-E
//    order       = W→E@strict
//    unknown     = W→E@strict
//    slot-arity  = W@lint , E@default , E@strict
//    evidence    = W-always
//    compound    = I-always
//    permissive  = W@default ; E@strict-parse  (Q3 settled Session-3-close)
// W! --strict  ⇒  any-W ∨ E  ⇒  exit-1
// W! --lint    ⇒  exit-0 always  (editor-surface mode)
// W! --strict-parse  ⇒  PERMISSIVE_ACCEPT → E (orthogonal to --strict)

import "core:fmt"
import "core:strings"

// --- known morpheme vocabulary (§03) ---
@(private="file")
MORPHEMES := [?]string{
    // aspect
    "prog", "perf", "iter", "hab", "inch", "term",
    // modality
    "must", "may", "cant", "will", "wont",
    // certainty
    "cert", "prob", "poss", "doubt",
    // scope
    "loc", "glob", "ctx",
}

Sem_Kind :: enum { Aspect, Modality, Certainty, Scope }

// --- T14 severity infrastructure ---

Sem_Mode :: enum { Lint, Default, Strict }

Sem_Severity :: enum { Info, Warn, Error }

Sem_Code :: enum {
    Morph_Order,           // aspect→mod→cert→scope violated
    Morph_Duplicate,       // two morphemes same category
    Morph_Unknown,         // suffix not in MORPHEMES
    Slot_Arity,            // reserved — future
    Evidence_Contradict,   // adjacent ✓ / ✗ on same subject
    Compound_Assoc,        // right-assoc detected
    Permissive_Accept,     // parser-accepted pattern flagged-under-strict
    // T21 IR diagnostics (CSL-{E,W,I}-3xx)
    Ir_Lower,              // lowering-level failure (unsupported form, nil, etc.)
    Ir_Region_Shape,       // wrong # of regions or wrong Region_Kind for op
    Ir_Missing_Terminator, // block does not end with a terminator op
    Ir_Use_Before_Def,     // operand referenced before its defining op/block-arg
    Ir_Type_Mismatch,      // operand/result type does not match op-signature
    Ir_Dangling_Value,     // Value.def_op/def_block not reachable from module
    Ir_Terminator_Kind,    // terminator is wrong kind for region (e.g. return in If_Then)
}

Sem_Diag :: struct {
    code:     Sem_Code,
    severity: Sem_Severity,
    pos:      Source_Pos,
    msg:      string,
}

sem_code_name :: proc(c: Sem_Code) -> string {
    switch c {
    case .Morph_Order:         return "CSL-W-001 morph-order"
    case .Morph_Duplicate:     return "CSL-E-002 morph-duplicate"
    case .Morph_Unknown:       return "CSL-W-003 morph-unknown"
    case .Slot_Arity:          return "CSL-W-004 slot-arity"
    case .Evidence_Contradict: return "CSL-W-005 evidence-contradict"
    case .Compound_Assoc:      return "CSL-I-006 compound-assoc"
    case .Permissive_Accept:   return "CSL-W-007 permissive-accept"
    case .Ir_Lower:              return "CSL-E-300 ir-lower"
    case .Ir_Region_Shape:       return "CSL-E-310 ir-region-shape"
    case .Ir_Missing_Terminator: return "CSL-E-311 ir-missing-terminator"
    case .Ir_Terminator_Kind:    return "CSL-E-312 ir-terminator-kind"
    case .Ir_Use_Before_Def:     return "CSL-E-320 ir-use-before-def"
    case .Ir_Type_Mismatch:      return "CSL-E-330 ir-type-mismatch"
    case .Ir_Dangling_Value:     return "CSL-E-340 ir-dangling-value"
    }
    return "CSL-?-000"
}

severity_label :: proc(s: Sem_Severity) -> string {
    switch s {
    case .Info:  return "info"
    case .Warn:  return "warn"
    case .Error: return "error"
    }
    return "?"
}

// Mode × Code → Severity. Matches Q2 table in DECISIONS.md Session-3-close.
severity_for :: proc(code: Sem_Code, mode: Sem_Mode, strict_parse: bool) -> Sem_Severity {
    switch code {
    case .Morph_Duplicate:
        return .Error  // always
    case .Morph_Order, .Morph_Unknown:
        return .Error if mode == .Strict else .Warn
    case .Slot_Arity:
        return .Warn if mode == .Lint else .Error
    case .Evidence_Contradict:
        return .Warn   // always-W
    case .Compound_Assoc:
        return .Info   // always-I
    case .Permissive_Accept:
        if strict_parse do return .Error
        return .Warn   // W@default @lint @strict (promoted only by --strict-parse)
    case .Ir_Lower,
         .Ir_Region_Shape,
         .Ir_Missing_Terminator,
         .Ir_Terminator_Kind,
         .Ir_Use_Before_Def,
         .Ir_Type_Mismatch,
         .Ir_Dangling_Value:
        return .Error   // IR-verifier structural failures always-E
    }
    return .Info
}

// --- result type ---

Semantic_Result :: struct {
    morphemes_detected: int,
    aliases_defined:    int,
    aliases_expanded:   int,
    scope_clauses:      int,
    suffixes_resolved:  int,
    compound_chains:    int,
    diagnostics:        [dynamic]Sem_Diag,
    aliases:            map[string]string,
    // exit-code decision inputs
    mode:               Sem_Mode,
    strict_parse:       bool,
}

semantic_result_init :: proc(r: ^Semantic_Result, mode: Sem_Mode = .Default, strict_parse: bool = false) {
    r.diagnostics  = make([dynamic]Sem_Diag)
    r.aliases      = make(map[string]string)
    r.mode         = mode
    r.strict_parse = strict_parse
}

semantic_result_destroy :: proc(r: ^Semantic_Result) {
    delete(r.diagnostics)
    delete(r.aliases)
}

@(private="file")
emit_diag :: proc(r: ^Semantic_Result, code: Sem_Code, pos: Source_Pos, msg: string) {
    sev := severity_for(code, r.mode, r.strict_parse)
    append(&r.diagnostics, Sem_Diag{code = code, severity = sev, pos = pos, msg = strings.clone(msg)})
}

// --- morpheme vocabulary helpers ---

is_morpheme_word :: proc(s: string) -> bool {
    for m in MORPHEMES {
        if m == s do return true
    }
    return false
}

morpheme_kind :: proc(s: string) -> (kind: Sem_Kind, ok: bool) {
    switch s {
    case "prog", "perf", "iter", "hab", "inch", "term":    return .Aspect,    true
    case "must", "may", "cant", "will", "wont":            return .Modality,  true
    case "cert", "prob", "poss", "doubt":                  return .Certainty, true
    case "loc", "glob", "ctx":                             return .Scope,     true
    }
    return .Aspect, false
}

@(private="file")
morph_category_name :: proc(k: Sem_Kind) -> string {
    switch k {
    case .Aspect:    return "aspect"
    case .Modality:  return "modality"
    case .Certainty: return "certainty"
    case .Scope:     return "scope"
    }
    return "?"
}

// --- alias handling ---

collect_aliases :: proc(n: ^Node, r: ^Semantic_Result) {
    if n == nil do return
    if n.kind == .Alias_Def {
        short := n.text
        expanded := compound_to_path(len(n.children) > 0 ? n.children[0] : nil)
        if len(short) > 0 && len(expanded) > 0 {
            r.aliases[short] = expanded
            r.aliases_defined += 1
        }
    }
    for c in n.children do collect_aliases(c, r)
    collect_aliases(n.gate, r)
    collect_aliases(n.scope, r)
    collect_aliases(n.type_expr, r)
    collect_aliases(n.constraint, r)
}

compound_to_path :: proc(n: ^Node) -> string {
    if n == nil do return ""
    #partial switch n.kind {
    case .Ident:
        return n.text
    case .Compound_Expr:
        if len(n.children) < 2 do return ""
        return fmt.tprintf("%s.%s", compound_to_path(n.children[0]), compound_to_path(n.children[1]))
    case:
        return n.text
    }
}

// --- morpheme hoist + alias expand walk ---

walk :: proc(n: ^Node, r: ^Semantic_Result) {
    if n == nil do return

    if n.kind == .Ident {
        if expansion, ok := r.aliases[n.text]; ok {
            n.text = expansion
            r.aliases_expanded += 1
        }
    }

    if n.kind == .Compound_Expr && n.op == .Dot {
        r.compound_chains += 1
        // T15 : preserve node.meta (permissive marker set by parse_postfix)
        // through the collapse, so check_permissive_accept still fires on
        // patterns like `render.prog.` where the compound was hoisted away.
        saved_meta := n.meta
        collapsed := collapse_morpheme_chain(n, r)
        if collapsed != nil && collapsed != n {
            n^ = collapsed^
            if len(saved_meta) > 0 && len(n.meta) == 0 {
                n.meta = saved_meta
            }
        }
    }

    if n.scope != nil do r.scope_clauses += 1
    if n.kind == .Scope_Clause do r.scope_clauses += 1

    if n.suffix != .Invalid do r.suffixes_resolved += 1

    for c in n.children do walk(c, r)
    walk(n.gate, r)
    walk(n.scope, r)
    walk(n.type_expr, r)
    walk(n.constraint, r)
}

collapse_morpheme_chain :: proc(compound: ^Node, r: ^Semantic_Result) -> ^Node {
    if compound == nil do return nil
    if compound.kind != .Compound_Expr || compound.op != .Dot do return compound
    if len(compound.children) < 2 do return compound

    lhs := compound.children[0]
    rhs := compound.children[1]

    // rhs must be a known morpheme to peel at this level.
    // if rhs is NOT a morpheme, leave compound intact. walk() will descend into
    // lhs on its own recursion pass — we must NOT pre-emptively recurse here
    // or the morpheme list gets double-appended when walk re-visits.
    if rhs.kind != .Ident || !is_morpheme_word(rhs.text) {
        return compound
    }

    // rhs IS a morpheme. Peel inner chain first (idempotent via walk's once-each),
    // then append this morpheme to the base.
    base := collapse_morpheme_chain(lhs, r) if (lhs.kind == .Compound_Expr && lhs.op == .Dot) else lhs
    append(&base.morphemes, rhs.text)
    r.morphemes_detected += 1
    return base
}

// --- T11 / T14 validity checks ---

@(private="file")
check_morpheme_stack :: proc(n: ^Node, r: ^Semantic_Result) {
    if len(n.morphemes) == 0 do return
    prev_rank := -1
    seen := [4]int{0, 0, 0, 0}
    for m in n.morphemes {
        kind, ok := morpheme_kind(m)
        if !ok {
            emit_diag(r, .Morph_Unknown, n.pos,
                fmt.tprintf("unknown morpheme '%s' on base '%s'", m, n.text))
            continue
        }
        rank := int(kind)
        seen[rank] += 1
        if seen[rank] > 1 {
            emit_diag(r, .Morph_Duplicate, n.pos,
                fmt.tprintf("duplicate morpheme category '%s' (%s) on base '%s'",
                    m, morph_category_name(kind), n.text))
        }
        if rank < prev_rank {
            emit_diag(r, .Morph_Order, n.pos,
                fmt.tprintf("morpheme '%s' (%s) out of canonical order on base '%s'",
                    m, morph_category_name(kind), n.text))
        }
        prev_rank = rank
    }
}

@(private="file")
check_slot_arity :: proc(n: ^Node, r: ^Semantic_Result) {
    // reserved — parser already enforces single-slot-prefix at parse time.
    // future: detect stale/contradictory slot state here.
}

@(private="file")
check_evidence_consistency :: proc(sec: ^Node, r: ^Semantic_Result) {
    if sec == nil || sec.kind != .Section do return
    prev_ev: Token_Kind = .Invalid
    prev_text := ""
    for c in sec.children {
        if c == nil do continue
        if c.evidence == .Invalid do continue
        subj := ""
        if len(c.children) > 0 && c.children[0] != nil {
            subj = c.children[0].text
        }
        if prev_ev != .Invalid && subj == prev_text {
            if (prev_ev == .Ev_Confirmed && c.evidence == .Ev_Failed) ||
               (prev_ev == .Ev_Failed && c.evidence == .Ev_Confirmed) {
                emit_diag(r, .Evidence_Contradict, c.pos,
                    fmt.tprintf("contradictory evidence on '%s' (%s vs %s)",
                        subj, token_kind_name(prev_ev), token_kind_name(c.evidence)))
            }
        }
        prev_ev = c.evidence
        prev_text = subj
    }
    for c in sec.children {
        if c != nil && c.kind == .Section do check_evidence_consistency(c, r)
    }
}

@(private="file")
check_compound_assoc :: proc(n: ^Node, r: ^Semantic_Result) {
    if n == nil || n.kind != .Compound_Expr do return
    if len(n.children) != 2 do return
    rhs := n.children[1]
    if rhs != nil && rhs.kind == .Compound_Expr {
        emit_diag(r, .Compound_Assoc, rhs.pos,
            "right-associative compound detected (expected left-assoc)")
    }
}

// T15 : Permissive-accept detection — parser-accepted shapes that strict-parse
// wants to reject. Called once per AST walk.
@(private="file")
check_permissive_accept :: proc(n: ^Node, r: ^Semantic_Result) {
    if n == nil do return
    // anonymous fn : fn () -> T = body
    if n.kind == .Function_Def && len(n.text) == 0 {
        emit_diag(r, .Permissive_Accept, n.pos,
            "anonymous function -- name required under --strict-parse")
    }
    // anonymous type : def = enum[...] or def = ⟨...⟩
    if (n.kind == .Type_Def || n.kind == .Enum_Def) && len(n.text) == 0 {
        emit_diag(r, .Permissive_Accept, n.pos,
            "anonymous type definition -- name required under --strict-parse")
    }
    // trailing operator meta : parser absorbed ". " / "@" / etc. into node.meta
    // because the statement ended with a dangling operator.
    if len(n.meta) > 0 {
        trimmed := strings.trim_left_space(n.meta)
        if len(trimmed) > 0 {
            c0 := trimmed[0]
            if c0 == '.' || c0 == '@' {
                emit_diag(r, .Permissive_Accept, n.pos,
                    fmt.tprintf("trailing operator '%c' absorbed as meta -- suspicious under --strict-parse", c0))
            }
        }
        // T22 : dedicated parser-side markers
        switch trimmed {
        case "slot-order":
            emit_diag(r, .Permissive_Accept, n.pos,
                "slot-prefix order : modal appeared before evidence (canonical is evidence → modal)")
        case "range-stmt":
            emit_diag(r, .Permissive_Accept, n.pos,
                "range expression used as a statement (did you mean a compound access?)")
        case "trailing-comma":
            emit_diag(r, .Permissive_Accept, n.pos,
                "trailing comma in tuple (dangling-element shape)")
        }
    }
    // bare modal directive : Directive with modal but empty payload.
    // ex : `W!` alone on a line, or `I>` with no body.
    if n.kind == .Directive && n.modal != .Invalid {
        if len(n.text) == 0 && len(n.children) == 0 {
            emit_diag(r, .Permissive_Accept, n.pos,
                fmt.tprintf("bare modal '%s' with no body -- suspicious under --strict-parse",
                    token_kind_name(n.modal)))
        }
    }
}

// Unknown-morpheme detection : a Compound_Expr(Dot) whose lhs already carries
// stacked morphemes (populated by collapse_morpheme_chain) and whose rhs is
// an Ident NOT in the morpheme vocabulary. Fires on `x.prog.fakebogus` etc.
@(private="file")
check_unknown_morpheme_tail :: proc(n: ^Node, r: ^Semantic_Result) {
    if n == nil || n.kind != .Compound_Expr || n.op != .Dot do return
    if len(n.children) < 2 do return
    lhs := n.children[0]
    rhs := n.children[1]
    if rhs == nil || rhs.kind != .Ident do return
    if is_morpheme_word(rhs.text) do return
    if lhs != nil && len(lhs.morphemes) > 0 {
        emit_diag(r, .Morph_Unknown, rhs.pos,
            fmt.tprintf("unknown morpheme '%s' after stack on '%s'",
                rhs.text, lhs.text))
    }
}

// --- orchestration ---

semantic_check_extended :: proc(doc: ^Node, r: ^Semantic_Result) {
    if doc == nil do return
    walk_check(doc, r)
    for c in doc.children {
        if c != nil && c.kind == .Section do check_evidence_consistency(c, r)
    }
}

@(private="file")
walk_check :: proc(n: ^Node, r: ^Semantic_Result) {
    if n == nil do return
    check_morpheme_stack(n, r)
    check_slot_arity(n, r)
    check_compound_assoc(n, r)
    check_permissive_accept(n, r)
    check_unknown_morpheme_tail(n, r)
    for c in n.children do walk_check(c, r)
    walk_check(n.gate, r)
    walk_check(n.scope, r)
    walk_check(n.type_expr, r)
    walk_check(n.constraint, r)
}

// --- entry points ---

// Back-compat : default mode, no strict-parse.
semantic_analyze :: proc(doc: ^Node) -> Semantic_Result {
    return semantic_analyze_with_mode(doc, .Default, false)
}

semantic_analyze_with_mode :: proc(doc: ^Node, mode: Sem_Mode, strict_parse: bool) -> Semantic_Result {
    r: Semantic_Result
    semantic_result_init(&r, mode, strict_parse)
    if doc == nil do return r

    collect_aliases(doc, &r)
    walk(doc, &r)
    semantic_check_extended(doc, &r)
    return r
}

// --- exit-code decision ---
// true = should exit 1.  Caller uses this + lex/parse error count.
semantic_fails :: proc(r: ^Semantic_Result) -> bool {
    if r.mode == .Lint do return false   // lint never-fails-on-diag
    for d in r.diagnostics {
        switch d.severity {
        case .Error:
            return true
        case .Warn:
            if r.mode == .Strict do return true
        case .Info:
            // never fails
        }
    }
    return false
}

// --- diagnostic counts for output formatting ---
semantic_counts :: proc(r: ^Semantic_Result) -> (info, warn, err: int) {
    for d in r.diagnostics {
        switch d.severity {
        case .Info:  info += 1
        case .Warn:  warn += 1
        case .Error: err  += 1
        }
    }
    return
}

// --- summary rendering ---
// verbose=true : include Info-level diagnostics in output.
semantic_render_summary :: proc(r: ^Semantic_Result, verbose: bool = false) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, "== semantic summary ==\n")
    strings.write_string(&sb, fmt.tprintf("mode:                   %s%s\n",
        sem_mode_name(r.mode),
        r.strict_parse ? " + strict-parse" : ""))
    strings.write_string(&sb, fmt.tprintf("compound chains walked: %d\n", r.compound_chains))
    strings.write_string(&sb, fmt.tprintf("morphemes detected:     %d\n", r.morphemes_detected))
    strings.write_string(&sb, fmt.tprintf("aliases defined:        %d\n", r.aliases_defined))
    strings.write_string(&sb, fmt.tprintf("aliases expanded:       %d\n", r.aliases_expanded))
    strings.write_string(&sb, fmt.tprintf("scope clauses:          %d\n", r.scope_clauses))
    strings.write_string(&sb, fmt.tprintf("type suffixes resolved: %d\n", r.suffixes_resolved))
    info, warn, err := semantic_counts(r)
    strings.write_string(&sb, fmt.tprintf("diagnostics:            info=%d warn=%d error=%d\n", info, warn, err))
    if len(r.aliases) > 0 {
        strings.write_string(&sb, "aliases:\n")
        for short, expanded in r.aliases {
            strings.write_string(&sb, fmt.tprintf("  %s -> %s\n", short, expanded))
        }
    }
    for d in r.diagnostics {
        if d.severity == .Info && !verbose do continue
        strings.write_string(&sb, fmt.tprintf("  [%s] %s:%d:%d %s : %s\n",
            severity_label(d.severity), d.pos.file, d.pos.line, d.pos.col,
            sem_code_name(d.code), d.msg))
    }
    return strings.to_string(sb)
}

sem_mode_name :: proc(m: Sem_Mode) -> string {
    switch m {
    case .Lint:    return "lint"
    case .Default: return "default"
    case .Strict:  return "strict"
    }
    return "?"
}
