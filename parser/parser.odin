package cslparser

// § CSLv3 PARSER — RECURSIVE-DESCENT
// I> LL(2) lookahead — peek up to 2 tokens ahead
// W! preserves slot template: evidence + modal + det + subject + relation + object + gate + scope + meta
// W! error recovery: synchronize to next statement boundary on parse failure

import "core:fmt"
import "core:strings"

Parse_Error :: struct {
    msg:     string,
    pos:     Source_Pos,
    snippet: string,
    context_: string,
}

Parser :: struct {
    tokens: []Token,
    idx:    int,
    file:   string,
    src:    string,
    errors: [dynamic]Parse_Error,
    // statement state (accumulated as slots are consumed)
    pending_evidence: Token_Kind,
    pending_modal:    Token_Kind,
    pending_det:      Token_Kind,
    // T23 (Session-5) : comments buffered between trivia skips,
    // attached to the next node created via attach_pending_comments().
    pending_comments: [dynamic]string,
}

parser_init :: proc(p: ^Parser, tokens: []Token, file: string, src: string) {
    p.tokens = tokens
    p.idx = 0
    p.file = file
    p.src = src
    p.errors = make([dynamic]Parse_Error)
    p.pending_evidence = .Invalid
    p.pending_modal = .Invalid
    p.pending_det = .Invalid
    p.pending_comments = make([dynamic]string)
}

parser_destroy :: proc(p: ^Parser) {
    delete(p.errors)
    delete(p.pending_comments)
}

// --- token access ---

@(private="file")
cur :: proc(p: ^Parser) -> ^Token {
    if p.idx >= len(p.tokens) do return &p.tokens[len(p.tokens)-1]
    return &p.tokens[p.idx]
}

@(private="file")
peek_at :: proc(p: ^Parser, offset: int) -> ^Token {
    i := p.idx + offset
    if i >= len(p.tokens) do return &p.tokens[len(p.tokens)-1]
    if i < 0 do return &p.tokens[0]
    return &p.tokens[i]
}

@(private="file")
peek_kind :: proc(p: ^Parser, offset := 0) -> Token_Kind {
    return peek_at(p, offset).kind
}

@(private="file")
advance :: proc(p: ^Parser) -> ^Token {
    t := cur(p)
    if p.idx < len(p.tokens) do p.idx += 1
    return t
}

@(private="file")
match_kind :: proc(p: ^Parser, k: Token_Kind) -> bool {
    if cur(p).kind == k {
        advance(p)
        return true
    }
    return false
}

@(private="file")
expect :: proc(p: ^Parser, k: Token_Kind, ctx: string = "") -> ^Token {
    if cur(p).kind == k {
        return advance(p)
    }
    add_parse_error(p, fmt.tprintf("expected %s, got %s", token_kind_name(k), token_kind_name(cur(p).kind)), cur(p).pos, ctx)
    return cur(p)
}

@(private="file")
at_eof :: proc(p: ^Parser) -> bool {
    return cur(p).kind == .EOF
}

// skip structural whitespace, statement separators, and comments (T23 Session-5).
// Comments are buffered into p.pending_comments so the next node-creator can
// claim them via attach_pending_comments.
@(private="file")
skip_newlines :: proc(p: ^Parser) {
    for {
        k := cur(p).kind
        if k == .Newline || k == .Semi {
            advance(p)
            continue
        }
        if k == .Comment {
            append(&p.pending_comments, strings.clone(cur(p).text))
            advance(p)
            continue
        }
        break
    }
}

@(private="file")
skip_blank :: proc(p: ^Parser) {
    skip_newlines(p)
}

@(private="file")
attach_pending_comments :: proc(p: ^Parser, n: ^Node) {
    if n == nil || len(p.pending_comments) == 0 do return
    for c in p.pending_comments {
        append(&n.comments_before, c)
    }
    clear(&p.pending_comments)
}

@(private="file")
add_parse_error :: proc(p: ^Parser, msg: string, pos: Source_Pos, ctx: string = "") {
    append(&p.errors, Parse_Error{
        msg = strings.clone(msg),
        pos = pos,
        snippet = line_snippet(p.src, pos.line),
        context_ = ctx,
    })
}

// --- slot scan ---
// consume evidence + modal + determinative at the start of a statement
// T22 addition : track order to flag modal-before-evidence as permissive-accept
@(private="file")
consume_slot_prefix :: proc(p: ^Parser) -> (evidence: Token_Kind, modal: Token_Kind, det: Token_Kind, bad_order: bool) {
    evidence = .Invalid
    modal = .Invalid
    det = .Invalid
    saw_modal_before_evidence := false
    for {
        k := cur(p).kind
        if evidence == .Invalid && token_is_evidence(k) {
            if modal != .Invalid do saw_modal_before_evidence = true
            evidence = k
            advance(p)
            continue
        }
        if modal == .Invalid && token_is_modal(k) {
            modal = k
            advance(p)
            continue
        }
        if det == .Invalid && (k == .Det_Field || k == .Det_Spatial) {
            det = k
            advance(p)
            continue
        }
        break
    }
    bad_order = saw_modal_before_evidence
    return
}

// is the current token a keyword usable as an ident in expression context?
@(private="file")
keyword_as_ident :: proc(k: Token_Kind) -> bool {
    #partial switch k {
    case .Kw_Fn, .Kw_Def, .Kw_Enum, .Kw_Let, .Kw_Pub, .Kw_Use, .Kw_Alias,
         .Kw_Match, .Kw_Per:
        return true
    }
    return false
}

// is this a token that indicates a structured statement (not prose)?
@(private="file")
is_structural_start :: proc(k: Token_Kind) -> bool {
    #partial switch k {
    case .Kw_Fn, .Kw_Def, .Kw_Let, .Kw_Pub, .Kw_Use, .Kw_Alias, .Kw_Match,
         .Kw_If, .Kw_When, .Kw_Unless, .Kw_While, .Kw_Enum,
         .ForAll, .Exists, .LConstraint, .LPre, .LFormula, .Section:
        return true
    }
    return false
}

// --- top-level entry ---

parse :: proc(p: ^Parser) -> ^Node {
    doc := make_node(.Document, cur(p).pos)
    skip_newlines(p)
    for !at_eof(p) {
        before := p.idx
        item := parse_top_item(p)
        if item != nil {
            node_add_child(doc, item)
        }
        // guarantee forward progress
        if p.idx == before {
            advance(p)
        }
        skip_newlines(p)
    }
    return doc
}

// a top-level item is either a Section or a statement
@(private="file")
parse_top_item :: proc(p: ^Parser) -> ^Node {
    if cur(p).kind == .Section do return parse_section(p, 1)
    return parse_statement(p)
}

// --- sections ---

@(private="file")
parse_section :: proc(p: ^Parser, caller_depth: int) -> ^Node {
    start_pos := cur(p).pos
    depth := 0
    for cur(p).kind == .Section {
        depth += 1
        advance(p)
    }
    sec := make_node(.Section, start_pos)
    sec.int_val = i64(depth)

    // heading: a compound name (ident chain)
    heading_sb := strings.builder_make()
    for {
        k := cur(p).kind
        if k == .Newline || k == .EOF || k == .Colon {
            break
        }
        // accept ident-like or common operators in heading
        if k == .Ident || keyword_as_ident(k) || token_is_primitive_type(k) ||
            k == .Dot || k == .Minus || k == .Plus || k == .Tensor ||
            token_is_suffix(k) || k == .Number {
            strings.write_string(&heading_sb, cur(p).text)
            advance(p)
        } else if token_is_evidence(k) {
            // evidence trailing a header (like "◐")
            sec.evidence = k
            advance(p)
        } else {
            break
        }
    }
    sec.text = strings.to_string(heading_sb)
    match_kind(p, .Colon)
    skip_newlines(p)

    // body: optional indented block (possibly after comment-only lines)
    if cur(p).kind == .Indent {
        advance(p)
        for !at_eof(p) && cur(p).kind != .Dedent {
            skip_newlines(p)
            if at_eof(p) || cur(p).kind == .Dedent do break
            // deeper subsections: more §s than caller
            if cur(p).kind == .Section {
                sub := parse_section(p, caller_depth + 1)
                node_add_child(sec, sub)
                continue
            }
            stmt := parse_statement(p)
            if stmt != nil do node_add_child(sec, stmt)
            skip_newlines(p)
        }
        if cur(p).kind == .Dedent do advance(p)
    }
    return sec
}

// --- statements ---

@(private="file")
parse_statement :: proc(p: ^Parser) -> ^Node {
    start_pos := cur(p).pos
    skip_newlines(p)
    if at_eof(p) do return nil

    // slot-prefix scan
    evidence, modal, det, bad_slot_order := consume_slot_prefix(p)

    // prose-directive short-circuit: I>, Q?, P>, D>, TODO, FIXME → capture line as raw text
    #partial switch modal {
    case .Modal_Insight, .Modal_Question, .Modal_Push, .Modal_Decision,
         .Modal_Todo, .Modal_Fixme:
        // only if followed by prose-ish content (not `fn`, `def`, `⌈`, `∀`, etc.)
        if !is_structural_start(cur(p).kind) {
            d := make_node(.Directive, start_pos)
            d.evidence = evidence
            d.modal = modal
            d.det = det
            sb := strings.builder_make()
            for !at_eof(p) && cur(p).kind != .Newline && cur(p).kind != .Dedent {
                if strings.builder_len(sb) > 0 do strings.write_rune(&sb, ' ')
                strings.write_string(&sb, cur(p).text)
                advance(p)
            }
            d.text = strings.to_string(sb)
            match_kind(p, .Newline)
            return d
        }
    }

    // post-prefix dispatch based on first meaningful token
    k := cur(p).kind
    n: ^Node

    #partial switch k {
    case .Newline, .EOF, .Dedent:
        // Only early-exit if no slot prefix was consumed. If prefix was set
        // (evidence/modal/det), fall through to the directive-fallback so a
        // bare `W!\n` or `[x]\n` emits a Directive node for T15.
        if evidence == .Invalid && modal == .Invalid && det == .Invalid {
            return nil
        }

    case .Section:
        n = parse_section(p, 2)

    case .Kw_Fn:
        n = parse_function_def(p)

    case .Kw_Def:
        n = parse_type_def(p)

    case .Kw_Alias:
        n = parse_alias_def(p)

    case .Kw_Use:
        n = parse_import(p)

    case .Kw_Pub:
        advance(p)
        inner := parse_statement(p)
        if inner != nil {
            exp := make_node(.Export, start_pos)
            node_add_child(exp, inner)
            n = exp
        }

    case .Kw_Match:
        n = parse_match(p)

    case .Kw_If, .Kw_When, .Kw_Unless, .Kw_While:
        n = parse_conditional_stmt(p)

    case .ForAll:
        n = parse_forall(p)

    case .Exists:
        n = parse_exists_stmt(p)

    case .LConstraint:
        n = parse_constraint_stmt(p)

    case .LPre:
        n = parse_precondition_stmt(p)

    case .LFormula:
        n = parse_formula_stmt(p)

    case .Kw_Let:
        n = parse_let_def(p)

    case .Modal_Todo, .Modal_Fixme:
        // already consumed if at slot prefix — this is fallback
        n = parse_directive_stmt(p)

    case:
        // statement starts with compound/expr → Definition | Relation | ExprStmt
        n = parse_expr_or_definition(p)
    }

    if n != nil {
        if n.evidence == .Invalid do n.evidence = evidence
        if n.modal == .Invalid do n.modal = modal
        if n.det == .Invalid do n.det = det
        // T23 : attach pending comments drained from skip_newlines into this stmt
        attach_pending_comments(p, n)
        // T22 : mark bad slot-prefix order (modal-before-evidence) for semantic check
        if bad_slot_order && len(n.meta) == 0 {
            n.meta = "slot-order"
        }
        // optional trailing gate / scope
        attach_trailing_slots(p, n)
        // absorb any trailing line content as meta (description / prose)
        if cur(p).kind != .Newline && cur(p).kind != .Dedent && cur(p).kind != .EOF {
            msb := strings.builder_make()
            for !at_eof(p) && cur(p).kind != .Newline && cur(p).kind != .Dedent {
                if strings.builder_len(msb) > 0 do strings.write_rune(&msb, ' ')
                strings.write_string(&msb, cur(p).text)
                advance(p)
            }
            n.meta = strings.to_string(msb)
        }
        // consume semicolons and newline as statement terminator
        for cur(p).kind == .Semi do advance(p)
        match_kind(p, .Newline)
        return n
    }
    // no body parsed — if slot prefix was non-empty, emit a Directive
    if evidence != .Invalid || modal != .Invalid || det != .Invalid {
        d := make_node(.Directive, start_pos)
        d.evidence = evidence
        d.modal = modal
        d.det = det
        match_kind(p, .Newline)
        return d
    }
    // synchronize to next statement boundary
    for !at_eof(p) && cur(p).kind != .Newline && cur(p).kind != .Dedent do advance(p)
    match_kind(p, .Newline)
    return nil
}

// post-statement gate / scope / meta attachments
@(private="file")
attach_trailing_slots :: proc(p: ^Parser, n: ^Node) {
    for {
        k := cur(p).kind
        if k == .Kw_If || k == .Kw_When || k == .Kw_Unless || k == .Kw_While {
            n.gate = parse_gate_clause(p)
            continue
        }
        if k == .At || k == .Kw_Per || k == .In {
            n.scope = parse_scope_clause(p)
            continue
        }
        break
    }
}

@(private="file")
parse_gate_clause :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    word := cur(p).text
    advance(p)
    g := make_node(.Gate_Clause, start)
    g.text = word
    node_add_child(g, parse_expr(p))
    return g
}

@(private="file")
parse_scope_clause :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    tag := cur(p).text
    advance(p)
    s := make_node(.Scope_Clause, start)
    s.text = tag
    s.op = .At
    // parse a compound target
    target := parse_compound(p)
    node_add_child(s, target)
    return s
}

// --- function def ---
// fn NAME ( PARAMS? ) ( -> TYPE )? ( = EXPR | BLOCK )?
@(private="file")
parse_function_def :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .Kw_Fn, "function definition")
    name := ""
    if cur(p).kind == .Ident {
        name = cur(p).text
        advance(p)
    }
    // else : anonymous fn (fn () -> ...) — leave name empty for T14 permissive-accept detection
    fn := make_node(.Function_Def, start)
    fn.text = name
    if token_is_suffix(cur(p).kind) {
        fn.suffix = cur(p).kind
        advance(p)
    }
    // parameters: (x :: T, y :: U) or ⟨x :: T, y :: U⟩
    params := make_node(.Block, cur(p).pos)
    open: Token_Kind = .Invalid
    close: Token_Kind = .Invalid
    if cur(p).kind == .LParen {
        open = .LParen; close = .RParen
    } else if cur(p).kind == .LAngle {
        open = .LAngle; close = .RAngle
    }
    if open != .Invalid {
        advance(p)
        for cur(p).kind != close && cur(p).kind != .Dedent && !at_eof(p) {
            _p_before := p.idx
            param := parse_param(p)
            if param != nil do node_add_child(params, param)
            if !match_kind(p, .Comma) do break
            if p.idx == _p_before do break
        }
        expect(p, close, "function parameter list")
    }
    node_add_child(fn, params)

    // return type: -> TYPE
    if match_kind(p, .Arrow_Right) {
        fn.type_expr = parse_type_expr(p)
    }

    // body: = EXPR  or  { block }  or  : INDENT block DEDENT
    if match_kind(p, .Eq) {
        body := make_node(.Block, cur(p).pos)
        // body may be multi-line via indent or single expression
        skip_inline_newline(p)
        if cur(p).kind == .Indent {
            advance(p)
            for cur(p).kind != .Dedent && cur(p).kind != .Dedent && !at_eof(p) {
                _p_before := p.idx
                s := parse_statement(p)
                if s != nil do node_add_child(body, s)
                skip_newlines(p)
                if p.idx == _p_before do break
            }
            match_kind(p, .Dedent)
        } else {
            // single expression body
            e := parse_expr(p)
            if e != nil do node_add_child(body, e)
        }
        node_add_child(fn, body)
    } else if cur(p).kind == .LBrace {
        node_add_child(fn, parse_block_braced(p))
    } else if cur(p).kind == .Colon {
        advance(p)
        skip_inline_newline(p)
        if cur(p).kind == .Indent {
            node_add_child(fn, parse_indent_block(p))
        }
    }
    return fn
}

@(private="file")
skip_inline_newline :: proc(p: ^Parser) {
    // skip any number of newlines/semis to tolerate comment-only lines
    for cur(p).kind == .Newline || cur(p).kind == .Semi do advance(p)
}

@(private="file")
parse_param :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    if cur(p).kind != .Ident && !keyword_as_ident(cur(p).kind) {
        return nil
    }
    name := cur(p).text
    advance(p)
    param := make_node(.Param_Decl, start)
    param.text = name
    if token_is_suffix(cur(p).kind) {
        param.suffix = cur(p).kind
        advance(p)
    }
    if match_kind(p, .DoubleColon) || match_kind(p, .Colon) {
        param.type_expr = parse_type_expr(p)
    }
    return param
}

@(private="file")
parse_indent_block :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    block := make_node(.Block, start)
    expect(p, .Indent, "block")
    for cur(p).kind != .Dedent && cur(p).kind != .Dedent && !at_eof(p) {
        _p_before := p.idx
        s := parse_statement(p)
        if s != nil do node_add_child(block, s)
        skip_newlines(p)
        if p.idx == _p_before do break
    }
    match_kind(p, .Dedent)
    return block
}

@(private="file")
parse_block_braced :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .LBrace, "braced block")
    block := make_node(.Block, start)
    for cur(p).kind != .RBrace && cur(p).kind != .Dedent && !at_eof(p) {
        _p_before := p.idx
        skip_newlines(p)
        if cur(p).kind == .RBrace do break
        s := parse_statement(p)
        if s != nil do node_add_child(block, s)
        skip_newlines(p)
        if p.idx == _p_before do break
    }
    expect(p, .RBrace, "end of braced block")
    return block
}

// --- type def & enum def ---
// def NAME SUFFIX? ⟨ field* ⟩
// def NAME SUFFIX? = enum[variant*]
@(private="file")
parse_type_def :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .Kw_Def, "type definition")
    name := ""
    if cur(p).kind == .Ident || keyword_as_ident(cur(p).kind) {
        name = cur(p).text
        advance(p)
    }
    // else : anonymous type (def = enum[...]) — leave name empty for T14 permissive-accept detection
    n := make_node(.Type_Def, start)
    n.text = name
    if token_is_suffix(cur(p).kind) {
        n.suffix = cur(p).kind
        advance(p)
    }
    if match_kind(p, .Eq) {
        // enum form
        if cur(p).kind == .Kw_Enum {
            advance(p)
            n.kind = .Enum_Def
            expect(p, .LBracket, "enum variant list")
            for cur(p).kind != .RBracket && cur(p).kind != .Dedent && !at_eof(p) {
                _p_before := p.idx
                skip_newlines(p)
                if cur(p).kind == .RBracket do break
                v := parse_variant(p)
                if v != nil do node_add_child(n, v)
                skip_newlines(p)
                match_kind(p, .Comma)
                if p.idx == _p_before do break
            }
            expect(p, .RBracket, "end of enum variant list")
            return n
        }
        // type alias: def X = T
        n.type_expr = parse_type_expr(p)
        return n
    }
    // record form: ⟨ field* ⟩ or { field* }
    open: Token_Kind = .Invalid
    close: Token_Kind = .Invalid
    if cur(p).kind == .LAngle { open = .LAngle; close = .RAngle }
    else if cur(p).kind == .LBrace { open = .LBrace; close = .RBrace }
    if open != .Invalid {
        advance(p)
        skip_newlines(p)
        for cur(p).kind != close && cur(p).kind != .Dedent && !at_eof(p) {
            _p_before := p.idx
            skip_newlines(p)
            if cur(p).kind == close do break
            f := parse_field(p)
            if f != nil do node_add_child(n, f)
            skip_newlines(p)
            match_kind(p, .Comma)
            if p.idx == _p_before do break
        }
        expect(p, close, "end of record definition")
    }
    return n
}

@(private="file")
parse_field :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    field := make_node(.Field_Decl, start)
    // optional determinative prefix like ∫moisture or §system
    if cur(p).kind == .Det_Field || cur(p).kind == .Det_Spatial {
        field.det = cur(p).kind
        advance(p)
    }
    if cur(p).kind != .Ident && !keyword_as_ident(cur(p).kind) {
        return nil
    }
    // field name may itself be a compound path (e.g., moisture.need)
    name_sb := strings.builder_make()
    strings.write_string(&name_sb, cur(p).text)
    advance(p)
    for cur(p).kind == .Dot {
        advance(p)
        if cur(p).kind == .Ident || keyword_as_ident(cur(p).kind) {
            strings.write_rune(&name_sb, '.')
            strings.write_string(&name_sb, cur(p).text)
            advance(p)
        } else {
            break
        }
    }
    field.text = strings.to_string(name_sb)
    if token_is_suffix(cur(p).kind) {
        field.suffix = cur(p).kind
        advance(p)
    }
    if match_kind(p, .Colon) || match_kind(p, .DoubleColon) {
        field.type_expr = parse_type_expr(p)
    }
    // constraint: ⌈ expr ⌉
    if cur(p).kind == .LConstraint {
        field.constraint = parse_constraint_expr(p)
    }
    // meta
    if cur(p).kind == .Hash {
        advance(p)
    }
    return field
}

@(private="file")
parse_variant :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    if cur(p).kind != .Ident && !keyword_as_ident(cur(p).kind) do return nil
    name := cur(p).text
    advance(p)
    v := make_node(.Variant_Decl, start)
    v.text = name
    // nested variants: ident { a, b, c }
    if cur(p).kind == .LBrace {
        advance(p)
        for cur(p).kind != .RBrace && cur(p).kind != .Dedent && !at_eof(p) {
            _p_before := p.idx
            skip_newlines(p)
            if cur(p).kind == .RBrace do break
            sub := parse_variant(p)
            if sub != nil do node_add_child(v, sub)
            skip_newlines(p)
            match_kind(p, .Comma)
            if p.idx == _p_before do break
        }
        match_kind(p, .RBrace)
    }
    return v
}

// --- alias def ---
// alias SHORT = LONG.COMPOUND.PATH
@(private="file")
parse_alias_def :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .Kw_Alias, "alias definition")
    n := make_node(.Alias_Def, start)
    if cur(p).kind == .Ident do n.text = cur(p).text
    advance(p)
    expect(p, .Eq, "alias")
    node_add_child(n, parse_compound(p))
    return n
}

// --- import ---
// use §module.name   or   use module.name
@(private="file")
parse_import :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .Kw_Use, "import")
    n := make_node(.Import, start)
    if cur(p).kind == .Section do advance(p)
    node_add_child(n, parse_compound(p))
    return n
}

// --- let binding ---
// let NAME (: TYPE)? = EXPR
@(private="file")
parse_let_def :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .Kw_Let, "let binding")
    n := make_node(.Definition, start)
    n.op = .Eq
    subj := make_node(.Ident, cur(p).pos)
    subj.text = cur(p).text
    advance(p)
    if token_is_suffix(cur(p).kind) {
        subj.suffix = cur(p).kind
        advance(p)
    }
    node_add_child(n, subj)
    if match_kind(p, .Colon) || match_kind(p, .DoubleColon) {
        n.type_expr = parse_type_expr(p)
    }
    if match_kind(p, .Eq) {
        node_add_child(n, parse_expr(p))
    }
    return n
}

// --- directive (modal prose) ---
@(private="file")
parse_directive_stmt :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    modal := cur(p).kind
    advance(p)
    n := make_node(.Directive, start)
    n.modal = modal
    // collect inline content as a single expression (loose)
    content := parse_expr(p)
    if content != nil do node_add_child(n, content)
    return n
}

// --- constraint ⌈ expr ⌉ ---
@(private="file")
parse_constraint_stmt :: proc(p: ^Parser) -> ^Node {
    // parse_constraint_expr already returns a Constraint node
    return parse_constraint_expr(p)
}

@(private="file")
parse_constraint_expr :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .LConstraint, "constraint")
    n := make_node(.Constraint, start)
    e := parse_expr(p)
    if e != nil do node_add_child(n, e)
    expect(p, .RConstraint, "end of constraint")
    return n
}

@(private="file")
parse_precondition_stmt :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .LPre, "precondition")
    n := make_node(.Precondition, start)
    e := parse_expr(p)
    if e != nil do node_add_child(n, e)
    expect(p, .RPre, "end of precondition")
    return n
}

@(private="file")
parse_formula_stmt :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .LFormula, "formula")
    n := make_node(.Formula, start)
    // accumulate formula body as raw text until ⟧
    sb := strings.builder_make()
    depth := 1
    for !at_eof(p) && depth > 0 {
        k := cur(p).kind
        if k == .LFormula { depth += 1 }
        else if k == .RFormula {
            depth -= 1
            if depth == 0 do break
        }
        if strings.builder_len(sb) > 0 do strings.write_rune(&sb, ' ')
        strings.write_string(&sb, cur(p).text)
        advance(p)
    }
    expect(p, .RFormula, "end of formula")
    n.text = strings.to_string(sb)
    return n
}

// --- forall ---
// ∀ var (∈ expr)? : block     or     ∀ var ∈ expr → expr
@(private="file")
parse_forall :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .ForAll, "∀")
    n := make_node(.ForAll_Stmt, start)
    // var
    if cur(p).kind == .Ident {
        n.text = cur(p).text
        advance(p)
    }
    // suffix
    if token_is_suffix(cur(p).kind) {
        n.suffix = cur(p).kind
        advance(p)
    }
    // domain
    if match_kind(p, .In) {
        node_add_child(n, parse_expr(p))
    }
    // body — colon+indent or → expr
    if match_kind(p, .Colon) {
        skip_inline_newline(p)
        if cur(p).kind == .Indent {
            node_add_child(n, parse_indent_block(p))
        } else {
            e := parse_expr(p)
            if e != nil do node_add_child(n, e)
        }
    } else if match_kind(p, .Arrow_Right) {
        e := parse_expr(p)
        if e != nil do node_add_child(n, e)
    }
    return n
}

@(private="file")
parse_exists_stmt :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .Exists, "∃")
    n := make_node(.Exists_Stmt, start)
    if cur(p).kind == .Ident {
        n.text = cur(p).text
        advance(p)
    }
    if match_kind(p, .In) {
        node_add_child(n, parse_expr(p))
    }
    if match_kind(p, .Colon) {
        e := parse_expr(p)
        if e != nil do node_add_child(n, e)
    }
    return n
}

// --- match ---
// match EXPR { (pattern → expr)* (* → expr)? }
@(private="file")
parse_match :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    expect(p, .Kw_Match, "match")
    n := make_node(.Match_Stmt, start)
    node_add_child(n, parse_expr(p))
    expect(p, .LBrace, "match body")
    for cur(p).kind != .RBrace && cur(p).kind != .Dedent && !at_eof(p) {
        _p_before := p.idx
        skip_newlines(p)
        if cur(p).kind == .RBrace do break
        arm_start := cur(p).pos
        arm := make_node(.Match_Arm, arm_start)
        pat := parse_expr(p)
        if pat != nil do node_add_child(arm, pat)
        if match_kind(p, .Arrow_Right) {
            body := parse_expr(p)
            if body != nil do node_add_child(arm, body)
        }
        node_add_child(n, arm)
        skip_newlines(p)
        match_kind(p, .Comma)
        if p.idx == _p_before do break
    }
    expect(p, .RBrace, "end of match")
    return n
}

// --- conditional statement: if/when/unless/while EXPR: BLOCK ---
@(private="file")
parse_conditional_stmt :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    word := cur(p).text
    advance(p)
    n := make_node(.Conditional, start)
    n.text = word
    node_add_child(n, parse_expr(p))
    if match_kind(p, .Colon) {
        skip_inline_newline(p)
        if cur(p).kind == .Indent {
            node_add_child(n, parse_indent_block(p))
        }
    } else if match_kind(p, .Arrow_Right) {
        body := parse_expr(p)
        if body != nil do node_add_child(n, body)
    }
    return n
}

// --- expression-or-definition dispatch ---
// Tries to parse: SUBJECT (:TYPE)? (=RHS)?  OR  SUBJECT REL_OP OBJECT  OR  bare EXPR
@(private="file")
parse_expr_or_definition :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    // parse lhs using primary-only form to preserve Definition/Relation split
    lhs := parse_primary_no_eq(p)
    if lhs == nil do return nil

    // detect COLON+INDENT as scope introduction → Conditional with block
    if cur(p).kind == .Colon && peek_kind(p, 1) == .Newline && peek_kind(p, 2) == .Indent {
        advance(p) // :
        skip_inline_newline(p)
        blk := parse_indent_block(p)
        cond := make_node(.Conditional, start)
        node_add_child(cond, lhs)
        node_add_child(cond, blk)
        return cond
    }

    k := cur(p).kind
    if k == .Colon || k == .DoubleColon {
        // definition with optional type + optional =
        def := make_node(.Definition, start)
        def.op = k
        node_add_child(def, lhs)
        advance(p)
        def.type_expr = parse_type_expr(p)
        if cur(p).kind == .LConstraint {
            def.constraint = parse_constraint_expr(p)
        }
        if match_kind(p, .Eq) {
            rhs := parse_expr(p)
            if rhs != nil do node_add_child(def, rhs)
        }
        return def
    }
    if k == .Eq {
        // assignment definition: subject = rhs
        def := make_node(.Definition, start)
        def.op = .Eq
        node_add_child(def, lhs)
        advance(p)
        rhs := parse_expr(p)
        if rhs != nil do node_add_child(def, rhs)
        return def
    }
    if k == .Plus_Eq || k == .Minus_Eq || k == .Star_Eq || k == .Slash_Eq {
        op := k
        advance(p)
        def := make_node(.Definition, start)
        def.op = op
        node_add_child(def, lhs)
        rhs := parse_expr(p)
        if rhs != nil do node_add_child(def, rhs)
        return def
    }
    if token_is_relation(k) || k == .Causes || k == .Arrow_Right || k == .Arrow_Left ||
       k == .Arrow_Bidi || k == .Implies {
        op := k
        advance(p)
        rel := make_node(.Relation, start)
        rel.op = op
        node_add_child(rel, lhs)
        rhs := parse_expr(p)
        if rhs != nil do node_add_child(rel, rhs)
        return rel
    }
    // trailing constraint: ... ⌈expr⌉
    if k == .LConstraint {
        cons := parse_constraint_expr(p)
        es := make_node(.Expr_Stmt, start)
        node_add_child(es, lhs)
        es.constraint = cons
        return es
    }
    // bare expression statement — continue parsing as full expression with lhs as primary
    full := extend_expr(p, lhs, 1)
    es := make_node(.Expr_Stmt, start)
    node_add_child(es, full)
    // T22 : flag range-at-statement-position (a..b alone = likely typo, not range-use)
    if full != nil && full.kind == .Binary && full.op == .Range {
        if len(es.meta) == 0 do es.meta = "range-stmt"
    }
    return es
}

// parse_primary_no_eq: a primary + postfix chain, no binary operators.
// Used as LHS of statement-level definition/relation so `=` remains as a splitter.
@(private="file")
parse_primary_no_eq :: proc(p: ^Parser) -> ^Node {
    return parse_postfix(p, parse_atom(p))
}

// extend_expr: given an already-parsed primary lhs, continue a binary expression from it
@(private="file")
extend_expr :: proc(p: ^Parser, lhs_in: ^Node, min_prec: int) -> ^Node {
    lhs := lhs_in
    for is_binop(cur(p).kind) {
        prec := binop_prec(cur(p).kind)
        if prec < min_prec do break
        op := cur(p).kind
        op_pos := cur(p).pos
        advance(p)
        rhs := parse_binary_expr(p, prec + 1)
        bin := make_node(.Binary, op_pos)
        bin.op = op
        node_add_child(bin, lhs)
        if rhs != nil do node_add_child(bin, rhs)
        lhs = bin
    }
    return lhs
}

// --- expressions: precedence climbing ---

// Operator precedence table (higher = tighter binding)
// 1: pipeline (|>)
// 2: flow (→ ⇒ ~> ↔)
// 3: logical or (||)
// 4: logical and (&&)
// 5: equality / identity (== != === ≈)
// 6: comparison (< > <= >=)
// 7: range (..)
// 8: additive (+ -)
// 9: multiplicative (* / %)
// 10: compound tatpurusha (.) and tensor (⊗)
// 11: unary (¬ ~ ! -)
// 12: postfix call / index / suffix
//
// Note: `.` is handled separately in parse_postfix as it's almost always compound access.
@(private="file")
binop_prec :: proc(k: Token_Kind) -> int {
    #partial switch k {
    case .PipeFwd, .PipeBack:          return 1
    case .Arrow_Right, .Arrow_Left,
         .Arrow_Bidi, .Implies, .Causes: return 2
    case .Or:                          return 3
    case .And:                         return 4
    case .Eq, .EqEq, .NotEq,
         .Identical, .Approx:          return 5
    case .Lt, .Gt, .Lte, .Gte:         return 6
    case .Range:                       return 7
    case .Plus, .Minus:                return 8
    case .Star, .Slash, .Percent,
         .Tensor, .Caret:              return 9
    case .Amp, .Pipe, .Xor:            return 4
    }
    return 0
}

@(private="file")
is_binop :: proc(k: Token_Kind) -> bool {
    return binop_prec(k) > 0
}

parse_expr :: proc(p: ^Parser) -> ^Node {
    return parse_binary_expr(p, 1)
}

@(private="file")
parse_binary_expr :: proc(p: ^Parser, min_prec: int) -> ^Node {
    lhs := parse_unary(p)
    if lhs == nil do return nil
    for is_binop(cur(p).kind) {
        prec := binop_prec(cur(p).kind)
        if prec < min_prec do break
        op := cur(p).kind
        op_pos := cur(p).pos
        advance(p)
        rhs := parse_binary_expr(p, prec + 1)
        bin := make_node(.Binary, op_pos)
        bin.op = op
        node_add_child(bin, lhs)
        if rhs != nil do node_add_child(bin, rhs)
        lhs = bin
    }
    // conditional: expr ? then : else
    if cur(p).kind == .Question {
        advance(p)
        then_branch := parse_binary_expr(p, 1)
        else_branch: ^Node
        if match_kind(p, .Colon) {
            else_branch = parse_binary_expr(p, 1)
        }
        cond := make_node(.Conditional, lhs.pos)
        node_add_child(cond, lhs)
        if then_branch != nil do node_add_child(cond, then_branch)
        if else_branch != nil do node_add_child(cond, else_branch)
        lhs = cond
    }
    return lhs
}

@(private="file")
parse_unary :: proc(p: ^Parser) -> ^Node {
    k := cur(p).kind
    if k == .Not || k == .Tilde || k == .Bang || k == .Minus {
        op := k
        start := cur(p).pos
        advance(p)
        operand := parse_unary(p)
        u := make_node(.Unary, start)
        u.op = op
        if operand != nil do node_add_child(u, operand)
        return u
    }
    return parse_postfix(p, parse_atom(p))
}

// postfix: call, index, type suffix, compound access (.), at-scope (@)
@(private="file")
parse_postfix :: proc(p: ^Parser, lhs_in: ^Node) -> ^Node {
    lhs := lhs_in
    if lhs == nil do return nil
    for {
        k := cur(p).kind
        if k == .Dot {
            // compound access: lhs.IDENT or lhs.IDENT.IDENT (absorb morpheme chain as well)
            advance(p)
            if cur(p).kind == .Ident || keyword_as_ident(cur(p).kind) {
                rhs := make_node(.Ident, cur(p).pos)
                rhs.text = cur(p).text
                advance(p)
                // absorb further chained ident suffix if morpheme-like — keep as compound
                c := make_node(.Compound_Expr, lhs.pos)
                c.op = .Dot
                node_add_child(c, lhs)
                node_add_child(c, rhs)
                lhs = c
            } else {
                // trailing dot absorbed — mark lhs as permissive-accept for T15.
                // check_permissive_accept reads node.meta starting with '.'.
                if len(lhs.meta) == 0 {
                    lhs.meta = "."
                }
                break
            }
            continue
        }
        if k == .LParen {
            // call
            advance(p)
            call := make_node(.Call, lhs.pos)
            node_add_child(call, lhs)
            for cur(p).kind != .RParen && cur(p).kind != .Dedent && !at_eof(p) {
                _p_before := p.idx
                a := parse_expr(p)
                if a != nil do node_add_child(call, a)
                if !match_kind(p, .Comma) do break
                if p.idx == _p_before do break
            }
            expect(p, .RParen, "call argument list")
            lhs = call
            continue
        }
        if k == .LAngle {
            // type arg / record call: foo⟨x, y⟩
            advance(p)
            call := make_node(.Call, lhs.pos)
            node_add_child(call, lhs)
            for cur(p).kind != .RAngle && cur(p).kind != .Dedent && !at_eof(p) {
                _p_before := p.idx
                a := parse_expr(p)
                if a != nil do node_add_child(call, a)
                if !match_kind(p, .Comma) do break
                if p.idx == _p_before do break
            }
            expect(p, .RAngle, "angle argument list")
            lhs = call
            continue
        }
        if k == .LBracket {
            // index
            advance(p)
            idx := make_node(.Index, lhs.pos)
            node_add_child(idx, lhs)
            a := parse_expr(p)
            if a != nil do node_add_child(idx, a)
            expect(p, .RBracket, "index expression")
            lhs = idx
            continue
        }
        if token_is_suffix(k) {
            // type suffix morpheme
            lhs.suffix = k
            advance(p)
            continue
        }
        if k == .Tensor {
            advance(p)
            rhs := parse_unary(p)
            c := make_node(.Compound_Expr, lhs.pos)
            c.op = .Tensor
            node_add_child(c, lhs)
            if rhs != nil do node_add_child(c, rhs)
            lhs = c
            continue
        }
        if k == .At {
            advance(p)
            // @scope — target is a compound
            sc := make_node(.Scope_Clause, lhs.pos)
            sc.op = .At
            sc.text = "@"
            target := parse_compound(p)
            if target != nil {
                node_add_child(sc, target)
            } else {
                // empty scope target — mark lhs meta for T15 Permissive_Accept
                if len(lhs.meta) == 0 {
                    lhs.meta = "@"
                }
            }
            lhs.scope = sc
            continue
        }
        break
    }
    return lhs
}

// atom: literal | ident (with possible compound) | group | record | list
@(private="file")
parse_atom :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    k := cur(p).kind
    #partial switch k {
    case .Number:
        n := make_node(.Num_Lit, start)
        n.text = cur(p).text
        n.int_val = cur(p).int_val
        n.float_val = cur(p).float_val
        n.is_float = cur(p).is_float
        advance(p)
        return n
    case .String:
        n := make_node(.Str_Lit, start)
        n.text = cur(p).text
        advance(p)
        return n
    case .Kw_True:
        advance(p)
        n := make_node(.Bool_Lit, start)
        n.bool_val = true
        return n
    case .Kw_False:
        advance(p)
        n := make_node(.Bool_Lit, start)
        n.bool_val = false
        return n
    case .Kw_Nil, .Empty:
        advance(p)
        return make_node(.Nil_Lit, start)
    case .Infinity:
        advance(p)
        n := make_node(.Num_Lit, start)
        n.text = "inf"
        n.float_val = 1e308
        n.is_float = true
        return n
    case .PosRef:
        advance(p)
        n := make_node(.PosRef, start)
        n.text = cur(p).text
        return n
    case .Dollar:
        n := make_node(.PosRef, start)
        n.text = cur(p).text
        advance(p)
        return n
    case .LParen:
        advance(p)
        e := parse_expr(p)
        // tuple: (a, b, c)
        if cur(p).kind == .Comma {
            tup := make_node(.Tuple_Expr, start)
            if e != nil do node_add_child(tup, e)
            for match_kind(p, .Comma) && cur(p).kind != .RParen && !at_eof(p) {
                el := parse_expr(p)
                if el != nil do node_add_child(tup, el)
            }
            expect(p, .RParen, "tuple")
            return tup
        }
        expect(p, .RParen, "group")
        g := make_node(.Group, start)
        if e != nil do node_add_child(g, e)
        return g
    case .LBracket:
        // list literal or array type context
        advance(p)
        list := make_node(.List_Expr, start)
        for cur(p).kind != .RBracket && cur(p).kind != .Dedent && !at_eof(p) {
            _p_before := p.idx
            e := parse_expr(p)
            if e != nil do node_add_child(list, e)
            if !match_kind(p, .Comma) do break
            if p.idx == _p_before do break
        }
        expect(p, .RBracket, "list literal")
        return list
    case .LAngle:
        // record literal ⟨ f = v, ... ⟩
        advance(p)
        rec := make_node(.Record_Expr, start)
        for cur(p).kind != .RAngle && cur(p).kind != .Dedent && !at_eof(p) {
            _p_before := p.idx
            skip_newlines(p)
            if cur(p).kind == .RAngle do break
            e := parse_expr(p)
            if e != nil do node_add_child(rec, e)
            if !match_kind(p, .Comma) do break
            skip_newlines(p)
            if p.idx == _p_before do break
        }
        expect(p, .RAngle, "record literal")
        return rec
    case .LBrace:
        // block expression
        return parse_block_braced(p)
    case .LConstraint:
        return parse_constraint_expr(p)
    case .LPre:
        return parse_precondition_stmt(p)
    case .LFormula:
        return parse_formula_stmt(p)
    case .Lambda, .Backslash:
        return parse_lambda(p)
    case .Ident:
        n := make_node(.Ident, start)
        n.text = cur(p).text
        advance(p)
        return n
    case:
        if keyword_as_ident(k) {
            n := make_node(.Ident, start)
            n.text = cur(p).text
            advance(p)
            return n
        }
        if token_is_primitive_type(k) {
            n := make_node(.Type_Prim, start)
            n.text = cur(p).text
            n.op = k
            advance(p)
            return n
        }
        // unknown atom — fabricate an ident with bare text to keep parsing going
        add_parse_error(p, fmt.tprintf("unexpected %s in expression", token_kind_name(k)), start)
        return nil
    }
}

// parse_compound: parse a dotted/compound-path on its own (used for alias, import, section heading)
@(private="file")
parse_compound :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    if cur(p).kind != .Ident && !keyword_as_ident(cur(p).kind) && !token_is_primitive_type(cur(p).kind) {
        return nil
    }
    first := make_node(.Ident, start)
    first.text = cur(p).text
    advance(p)
    lhs: ^Node = first
    for cur(p).kind == .Dot {
        advance(p)
        if cur(p).kind == .Ident || keyword_as_ident(cur(p).kind) {
            rhs := make_node(.Ident, cur(p).pos)
            rhs.text = cur(p).text
            advance(p)
            c := make_node(.Compound_Expr, lhs.pos)
            c.op = .Dot
            node_add_child(c, lhs)
            node_add_child(c, rhs)
            lhs = c
        } else {
            break
        }
    }
    if token_is_suffix(cur(p).kind) {
        lhs.suffix = cur(p).kind
        advance(p)
    }
    return lhs
}

// --- lambda ---
// λ(params) → expr       or       \(params) -> expr
@(private="file")
parse_lambda :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    advance(p) // consume λ or \
    lam := make_node(.Lambda, start)
    if match_kind(p, .LParen) {
        for cur(p).kind != .RParen && cur(p).kind != .Dedent && !at_eof(p) {
            _p_before := p.idx
            param := parse_param(p)
            if param != nil do node_add_child(lam, param)
            if !match_kind(p, .Comma) do break
            if p.idx == _p_before do break
        }
        expect(p, .RParen, "lambda params")
    } else if match_kind(p, .LAngle) {
        for cur(p).kind != .RAngle && cur(p).kind != .Dedent && !at_eof(p) {
            _p_before := p.idx
            param := parse_param(p)
            if param != nil do node_add_child(lam, param)
            if !match_kind(p, .Comma) do break
            if p.idx == _p_before do break
        }
        expect(p, .RAngle, "lambda params")
    }
    if match_kind(p, .Arrow_Right) {
        body := parse_expr(p)
        if body != nil do node_add_child(lam, body)
    }
    return lam
}

// --- type expressions ---
parse_type_expr :: proc(p: ^Parser) -> ^Node {
    return parse_type_arrow(p)
}

// right-associative arrow type: T -> U -> V  ==  T -> (U -> V)
@(private="file")
parse_type_arrow :: proc(p: ^Parser) -> ^Node {
    lhs := parse_type_union(p)
    if lhs == nil do return nil
    if cur(p).kind == .Arrow_Right {
        advance(p)
        rhs := parse_type_arrow(p)
        arr := make_node(.Type_Tuple, lhs.pos)
        arr.op = .Arrow_Right
        node_add_child(arr, lhs)
        if rhs != nil do node_add_child(arr, rhs)
        return arr
    }
    return lhs
}

@(private="file")
parse_type_union :: proc(p: ^Parser) -> ^Node {
    lhs := parse_type_post(p)
    if lhs == nil do return nil
    for cur(p).kind == .Pipe {
        advance(p)
        rhs := parse_type_post(p)
        u := make_node(.Type_Union, lhs.pos)
        node_add_child(u, lhs)
        if rhs != nil do node_add_child(u, rhs)
        lhs = u
    }
    return lhs
}

// handle postfix type modifiers: T? T! T&
@(private="file")
parse_type_post :: proc(p: ^Parser) -> ^Node {
    lhs := parse_type_primary(p)
    if lhs == nil do return nil
    for {
        k := cur(p).kind
        if k == .Question {
            advance(p)
            opt := make_node(.Type_Opt, lhs.pos)
            node_add_child(opt, lhs)
            lhs = opt
            continue
        }
        if k == .Bang {
            // T! — might be T!lin
            advance(p)
            if cur(p).kind == .Ident && cur(p).text == "lin" {
                advance(p)
                lin := make_node(.Type_Linear, lhs.pos)
                node_add_child(lin, lhs)
                lhs = lin
            } else {
                res := make_node(.Type_Result, lhs.pos)
                node_add_child(res, lhs)
                lhs = res
            }
            continue
        }
        if k == .Amp {
            // &T (already handled in primary for prefix) — here handles postfix borrow T&
            advance(p)
            if cur(p).kind == .Ident && cur(p).text == "mut" {
                advance(p)
                mr := make_node(.Type_Mut_Ref, lhs.pos)
                node_add_child(mr, lhs)
                lhs = mr
            } else {
                ref := make_node(.Type_Ref, lhs.pos)
                node_add_child(ref, lhs)
                lhs = ref
            }
            continue
        }
        break
    }
    return lhs
}

@(private="file")
parse_type_primary :: proc(p: ^Parser) -> ^Node {
    start := cur(p).pos
    k := cur(p).kind
    if token_is_primitive_type(k) {
        n := make_node(.Type_Prim, start)
        n.text = cur(p).text
        n.op = k
        advance(p)
        return n
    }
    if k == .Amp {
        advance(p)
        inner := parse_type_primary(p)
        if cur(p).kind == .Ident && cur(p).text == "mut" {
            advance(p)
            inner2 := parse_type_primary(p)
            mr := make_node(.Type_Mut_Ref, start)
            if inner2 != nil do node_add_child(mr, inner2)
            return mr
        }
        ref := make_node(.Type_Ref, start)
        if inner != nil do node_add_child(ref, inner)
        return ref
    }
    if k == .Star {
        advance(p)
        inner := parse_type_primary(p)
        // collection type — represent as array
        arr := make_node(.Type_Array, start)
        if inner != nil do node_add_child(arr, inner)
        return arr
    }
    if k == .LBracket {
        advance(p)
        elem := parse_type_expr(p)
        arr := make_node(.Type_Array, start)
        if elem != nil do node_add_child(arr, elem)
        if match_kind(p, .Semi) {
            // length
            if cur(p).kind == .Number {
                len_node := make_node(.Num_Lit, cur(p).pos)
                len_node.text = cur(p).text
                len_node.int_val = cur(p).int_val
                advance(p)
                node_add_child(arr, len_node)
            } else if cur(p).kind == .Underscore {
                advance(p) // dynamic length
                dyn := make_node(.Ident, cur(p).pos)
                dyn.text = "_"
                node_add_child(arr, dyn)
            }
        }
        expect(p, .RBracket, "array type")
        return arr
    }
    if k == .LParen {
        advance(p)
        first := parse_type_expr(p)
        if cur(p).kind == .Comma {
            tup := make_node(.Type_Tuple, start)
            if first != nil do node_add_child(tup, first)
            trailing_comma := false
            for match_kind(p, .Comma) && cur(p).kind != .RParen {
                // T22 : detect trailing comma — if next is RParen, no element to parse
                if cur(p).kind == .RParen {
                    trailing_comma = true
                    break
                }
                el := parse_type_expr(p)
                if el != nil do node_add_child(tup, el)
                else { trailing_comma = true; break }
            }
            // detect `(T,)` single-elem trailing-comma as permissive
            if len(tup.children) == 1 && cur(p).kind == .RParen {
                trailing_comma = true
            }
            expect(p, .RParen, "tuple type")
            if trailing_comma && len(tup.meta) == 0 {
                tup.meta = "trailing-comma"
            }
            return tup
        }
        expect(p, .RParen, "group type")
        return first
    }
    if k == .LBrace {
        advance(p)
        // { K : V }  map
        keyt := parse_type_expr(p)
        if match_kind(p, .Colon) {
            valt := parse_type_expr(p)
            expect(p, .RBrace, "map type")
            m := make_node(.Type_Map, start)
            if keyt != nil do node_add_child(m, keyt)
            if valt != nil do node_add_child(m, valt)
            return m
        }
        // refinement { x:T ⊢ P }
        expect(p, .RBrace, "refinement type")
        r := make_node(.Type_Refinement, start)
        if keyt != nil do node_add_child(r, keyt)
        return r
    }
    if k == .LAngle {
        advance(p)
        rec := make_node(.Type_Record, start)
        for cur(p).kind != .RAngle && cur(p).kind != .Dedent && !at_eof(p) {
            _p_before := p.idx
            skip_newlines(p)
            if cur(p).kind == .RAngle do break
            f := parse_field(p)
            if f != nil do node_add_child(rec, f)
            skip_newlines(p)
            match_kind(p, .Comma)
            if p.idx == _p_before do break
        }
        expect(p, .RAngle, "record type")
        return rec
    }
    // named type (possibly compound)
    if k == .Ident || keyword_as_ident(k) {
        return parse_compound(p)
    }
    add_parse_error(p, fmt.tprintf("expected type, got %s", token_kind_name(k)), start)
    return nil
}

// --- public runner ---
parse_source :: proc(src: string, file: string) -> (doc: ^Node, lex_errors: []Lex_Error, parse_errors: []Parse_Error) {
    tokens, lerrs := lex_source(src, file)
    lex_errors = lerrs
    p: Parser
    parser_init(&p, tokens, file, src)
    doc = parse(&p)
    parse_errors = p.errors[:]
    return
}
