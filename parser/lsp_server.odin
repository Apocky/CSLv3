package cslparser

// § B1 Session-14 : Phase-B LSP server scaffolding (Odin-native).
//
// I> replaces : Rust tower-lsp / tokio / lsp-types stack (D5-D29, 50+ crates)
//    with a self-contained Odin implementation that reuses A4 json_codec
//    for message serialization.
// I> This is the MVP : JSON-RPC message loop + initialize/initialized +
//    textDocument/didOpen/didChange/didClose + publishDiagnostics hook.
//    Additional LSP methods (hover, definition, completion, codeAction,
//    rename, formatting) are phase-B continuations for Session-15+.
// I> The existing Rust LSP stays in lsp/server/ as the reference ; this
//    Odin path is feature-equivalent-at-the-MVP-level and demonstrates
//    the post-v2 zero-Rust deployment target.
//
// Invocation :
//   parser.exe --lsp                  ← speaks LSP over stdin/stdout
//
// Wire format : LSP uses HTTP-like headers followed by a JSON body.
//   Content-Length: <n>\r\n
//   \r\n
//   {<n bytes JSON>}
//
// Spec-cite : LSP specification 3.17 (https://microsoft.github.io/
// language-server-protocol/specifications/lsp/3.17/specification/).

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

@(private="file")
LSP_SERVER_NAME    :: "cslv3-lsp-odin"
@(private="file")
LSP_SERVER_VERSION :: "0.1.0"   // bumps with parser.exe

// One document we've been told about.
@(private="file")
Lsp_Doc :: struct {
    uri:      string,
    version:  i64,
    language: string,
    text:     string,
}

@(private="file")
Lsp_State :: struct {
    initialized: bool,
    shutdown_requested: bool,
    docs: map[string]Lsp_Doc,
}

// ------------------------- wire layer -------------------------

@(private="file")
read_message :: proc() -> (body: []u8, ok: bool) {
    // Read headers until blank line, then body of Content-Length bytes.
    content_length := -1
    hdr_buf: [1024]u8
    hdr_len := 0
    // byte-at-a-time until we see "\r\n\r\n"
    for {
        ch: [1]u8
        n, err := os.read(os.stdin, ch[:])
        if err != os.ERROR_NONE || n == 0 do return nil, false
        if hdr_len >= len(hdr_buf) do return nil, false
        hdr_buf[hdr_len] = ch[0]
        hdr_len += 1
        if hdr_len >= 4 &&
           hdr_buf[hdr_len-4] == '\r' && hdr_buf[hdr_len-3] == '\n' &&
           hdr_buf[hdr_len-2] == '\r' && hdr_buf[hdr_len-1] == '\n' {
            break
        }
    }
    headers := string(hdr_buf[:hdr_len])
    for line in strings.split_lines_iterator(&headers) {
        ln := strings.trim_right(line, "\r")
        if len(ln) == 0 do continue
        if colon := strings.index_byte(ln, ':'); colon > 0 {
            name := strings.trim_space(ln[:colon])
            val  := strings.trim_space(ln[colon+1:])
            if strings.equal_fold(name, "Content-Length") {
                content_length, _ = strconv.parse_int(val)
            }
        }
    }
    if content_length < 0 do return nil, false
    body = make([]u8, content_length)
    read := 0
    for read < content_length {
        n, err := os.read(os.stdin, body[read:])
        if err != os.ERROR_NONE || n == 0 {
            delete(body)
            return nil, false
        }
        read += n
    }
    return body, true
}

@(private="file")
write_message :: proc(body_json: string) {
    header := fmt.tprintf("Content-Length: %d\r\n\r\n", len(body_json))
    os.write_string(os.stdout, header)
    os.write_string(os.stdout, body_json)
}

// ------------------------- response helpers -------------------------

@(private="file")
mk_response :: proc(id: ^J_Value, result: ^J_Value) -> ^J_Value {
    r := new(J_Value)
    r.kind = .Object
    k_jsonrpc := strings.clone("jsonrpc")
    v_jsonrpc := new(J_Value); v_jsonrpc.kind = .String; v_jsonrpc.s = strings.clone("2.0")
    append(&r.obj_keys, k_jsonrpc); append(&r.obj_vals, v_jsonrpc)
    if id != nil {
        k_id := strings.clone("id")
        append(&r.obj_keys, k_id); append(&r.obj_vals, clone_j(id))
    }
    k_res := strings.clone("result")
    append(&r.obj_keys, k_res); append(&r.obj_vals, result)
    return r
}

@(private="file")
mk_notification :: proc(method: string, params: ^J_Value) -> ^J_Value {
    r := new(J_Value)
    r.kind = .Object
    k_jsonrpc := strings.clone("jsonrpc")
    v_jsonrpc := new(J_Value); v_jsonrpc.kind = .String; v_jsonrpc.s = strings.clone("2.0")
    append(&r.obj_keys, k_jsonrpc); append(&r.obj_vals, v_jsonrpc)
    k_method := strings.clone("method")
    v_method := new(J_Value); v_method.kind = .String; v_method.s = strings.clone(method)
    append(&r.obj_keys, k_method); append(&r.obj_vals, v_method)
    k_params := strings.clone("params")
    append(&r.obj_keys, k_params); append(&r.obj_vals, params)
    return r
}

@(private="file")
clone_j :: proc(v: ^J_Value) -> ^J_Value {
    if v == nil do return nil
    nv := new(J_Value)
    nv.kind = v.kind
    switch v.kind {
    case .Null:
    case .Bool:   nv.b = v.b
    case .Number: nv.n = v.n ; nv.n_is_int = v.n_is_int ; nv.n_int = v.n_int
    case .String: nv.s = strings.clone(v.s)
    case .Array:
        for e in v.arr do append(&nv.arr, clone_j(e))
    case .Object:
        for k, i in v.obj_keys {
            append(&nv.obj_keys, strings.clone(k))
            append(&nv.obj_vals, clone_j(v.obj_vals[i]))
        }
    }
    return nv
}

@(private="file")
j_obj :: proc() -> ^J_Value {
    r := new(J_Value)
    r.kind = .Object
    return r
}

@(private="file")
j_put :: proc(o: ^J_Value, key: string, val: ^J_Value) {
    append(&o.obj_keys, strings.clone(key))
    append(&o.obj_vals, val)
}

@(private="file")
j_str :: proc(s: string) -> ^J_Value {
    v := new(J_Value); v.kind = .String; v.s = strings.clone(s); return v
}

@(private="file")
j_int :: proc(i: i64) -> ^J_Value {
    v := new(J_Value); v.kind = .Number; v.n = f64(i); v.n_is_int = true; v.n_int = i; return v
}

@(private="file")
j_bool :: proc(b: bool) -> ^J_Value {
    v := new(J_Value); v.kind = .Bool; v.b = b; return v
}

@(private="file")
j_null :: proc() -> ^J_Value {
    v := new(J_Value); v.kind = .Null; return v
}

@(private="file")
j_arr :: proc() -> ^J_Value {
    v := new(J_Value); v.kind = .Array; return v
}

// ------------------------- method handlers -------------------------

@(private="file")
build_capabilities :: proc() -> ^J_Value {
    caps := j_obj()
    // textDocumentSync : Full sync (1) — the MVP re-parses entire doc on change.
    j_put(caps, "textDocumentSync", j_int(1))
    // diagnosticProvider is pushed ; we publish via notification.
    // Position encoding : UTF-16 (LSP default).
    j_put(caps, "positionEncoding", j_str("utf-16"))
    // Session-17 Phase-B : hover + completion + documentSymbol
    hover_prov := j_obj()
    j_put(caps, "hoverProvider", hover_prov)
    compl_prov := j_obj()
    trig := j_arr()
    append(&trig.arr, j_str("§"))
    append(&trig.arr, j_str(":"))
    append(&trig.arr, j_str("."))
    append(&trig.arr, j_str("W"))  // W! R! N! I>
    j_put(compl_prov, "triggerCharacters", trig)
    j_put(caps, "completionProvider", compl_prov)
    j_put(caps, "documentSymbolProvider", j_bool(true))
    return caps
}

@(private="file")
handle_initialize :: proc(state: ^Lsp_State, params: ^J_Value, id: ^J_Value) -> ^J_Value {
    result := j_obj()
    caps := build_capabilities()
    j_put(result, "capabilities", caps)
    info := j_obj()
    j_put(info, "name", j_str(LSP_SERVER_NAME))
    j_put(info, "version", j_str(LSP_SERVER_VERSION))
    j_put(result, "serverInfo", info)
    state.initialized = true
    return mk_response(id, result)
}

@(private="file")
handle_shutdown :: proc(state: ^Lsp_State, id: ^J_Value) -> ^J_Value {
    state.shutdown_requested = true
    return mk_response(id, j_null())
}

@(private="file")
position_to_offset :: proc(text: string, line_i, char_i: int) -> int {
    // Line-and-column (0-based) → byte offset. UTF-16 character count
    // approximation : treat each UTF-8 byte as 1 char (correct for ASCII ;
    // UTF-16 subtleties are a Session-15 polish item).
    line := 0
    off := 0
    for i in 0 ..< len(text) {
        if line == line_i {
            // walk char_i chars from here
            return min(off + char_i, len(text))
        }
        if text[i] == '\n' {
            line += 1
            off = i + 1
        }
    }
    return len(text)
}

@(private="file")
apply_did_change :: proc(doc: ^Lsp_Doc, content_changes: ^J_Value) {
    if content_changes == nil || content_changes.kind != .Array do return
    for change in content_changes.arr {
        if change.kind != .Object do continue
        // Full-sync shape : { "text": "<full doc>" }
        if text_val := get_prop(change, "text"); text_val != nil && text_val.kind == .String {
            delete(doc.text)
            doc.text = strings.clone(text_val.s)
        }
    }
}

// Re-run parser on a document and emit publishDiagnostics notification.
@(private="file")
publish_diagnostics :: proc(uri: string, text: string) {
    // Session-15 O3 : surface both lex AND parse errors. parse_source
    // runs the full pipeline and returns three slices (doc, lex, parse).
    _, lex_errs, parse_errs := parse_source(text, uri)
    defer { for e in lex_errs do delete(e.snippet) ; delete(lex_errs) }
    defer { for e in parse_errs do delete(e.snippet) ; delete(parse_errs) }

    diags := j_arr()
    for le in lex_errs {
        d := j_obj()
        rng := j_obj()
        s := j_obj(); j_put(s, "line", j_int(i64(max(0, le.pos.line - 1))))
                      j_put(s, "character", j_int(i64(max(0, le.pos.col - 1))))
        e := j_obj(); j_put(e, "line", j_int(i64(max(0, le.pos.line - 1))))
                      j_put(e, "character", j_int(i64(le.pos.col)))
        j_put(rng, "start", s)
        j_put(rng, "end",   e)
        j_put(d, "range", rng)
        j_put(d, "severity", j_int(1))  // Error
        j_put(d, "source", j_str("cslv3-lsp"))
        j_put(d, "code", j_str("lex"))
        j_put(d, "message", j_str(le.msg))
        append(&diags.arr, d)
    }
    for pe in parse_errs {
        d := j_obj()
        rng := j_obj()
        s := j_obj(); j_put(s, "line", j_int(i64(max(0, pe.pos.line - 1))))
                      j_put(s, "character", j_int(i64(max(0, pe.pos.col - 1))))
        e := j_obj(); j_put(e, "line", j_int(i64(max(0, pe.pos.line - 1))))
                      j_put(e, "character", j_int(i64(pe.pos.col)))
        j_put(rng, "start", s)
        j_put(rng, "end",   e)
        j_put(d, "range", rng)
        j_put(d, "severity", j_int(1))  // Error
        j_put(d, "source", j_str("cslv3-lsp"))
        j_put(d, "code", j_str("parse"))
        msg := pe.msg
        if len(pe.context_) > 0 do msg = fmt.tprintf("%s (%s)", pe.msg, pe.context_)
        j_put(d, "message", j_str(msg))
        append(&diags.arr, d)
    }

    params := j_obj()
    j_put(params, "uri", j_str(uri))
    j_put(params, "diagnostics", diags)
    notif := mk_notification("textDocument/publishDiagnostics", params)
    body := json_emit(notif, false, context.temp_allocator)
    write_message(body)
    json_free(notif)
}

@(private="file")
handle_did_open :: proc(state: ^Lsp_State, params: ^J_Value) {
    td := get_prop(params, "textDocument")
    if td == nil do return
    uri, _ := get_str_from(td, "uri")
    text, _ := get_str_from(td, "text")
    lang, _ := get_str_from(td, "languageId")
    ver_p := get_prop(td, "version")
    ver : i64 = 0
    if ver_p != nil && ver_p.kind == .Number do ver = ver_p.n_int if ver_p.n_is_int else i64(ver_p.n)
    doc := Lsp_Doc{
        uri = strings.clone(uri),
        version = ver,
        language = strings.clone(lang),
        text = strings.clone(text),
    }
    state.docs[doc.uri] = doc
    publish_diagnostics(doc.uri, doc.text)
}

@(private="file")
handle_did_change :: proc(state: ^Lsp_State, params: ^J_Value) {
    td := get_prop(params, "textDocument")
    if td == nil do return
    uri, _ := get_str_from(td, "uri")
    ver_p := get_prop(td, "version")
    if _, ok := state.docs[uri]; ok {
        d := &state.docs[uri]
        if ver_p != nil && ver_p.kind == .Number do d.version = ver_p.n_int if ver_p.n_is_int else i64(ver_p.n)
        changes := get_prop(params, "contentChanges")
        apply_did_change(d, changes)
        publish_diagnostics(d.uri, d.text)
    }
}

// ---------- hover / completion / documentSymbol ----------

// Tiny glyph-reference table for hover-over-glyph. Lookups by glyph text.
@(private="file")
Glyph_Info :: struct { glyph, ascii, meaning: string }

@(private="file")
GLYPH_TABLE := []Glyph_Info{
    {"§", "S:", "section / module / domain boundary"},
    {"¶", "P:", "sub-paragraph / continuation"},
    {"→", "->", "then / yields / maps-to / flow"},
    {"←", "<-", "from / sourced / derives"},
    {"↔", "<->", "bidirectional / isomorphic"},
    {"⇒", "=>", "implies (logical)"},
    {"⊢", "|-", "entails / proves"},
    {"∴", ".:.", "therefore"},
    {"∵", ":..", "because"},
    {"∎", "QED", "block-end / proof-end"},
    {"W!", "W!", "MUST (hard requirement, inviolable)"},
    {"R!", "R!", "SHOULD (strong recommend)"},
    {"M?", "M?", "MAY (optional, designer discretion)"},
    {"N!", "N!", "MUST NOT (prohibition)"},
    {"I>", "I>", "INSIGHT / key claim / important note"},
    {"Q?", "Q?", "QUESTION / open question"},
    {"✓", "[x]", "confirmed / true / verified"},
    {"◐", "[~]", "partial / probable / in-progress"},
    {"○", "[ ]", "pending / possible / unknown"},
    {"✗", "[!]", "failed / false / blocked / rejected"},
    {"⊗", "x*", "bahuvrihi compound (having X-Y)"},
    {"⊕", "xor", "exclusive or"},
    {"∀", "all", "for all / universal quantifier"},
    {"∃", "any", "exists / existential quantifier"},
    {"∈", "in", "member-of"},
    {"⊆", "<:", "subset"},
    {"⊂", "<:", "strict-subset"},
    {"∪", "|+", "union"},
    {"∩", "&+", "intersect"},
    {"@", "@", "avyayibhava (at / per / in scope of)"},
}

@(private="file")
glyph_info :: proc(g: string) -> (Glyph_Info, bool) {
    for gi in GLYPH_TABLE do if gi.glyph == g do return gi, true
    return Glyph_Info{}, false
}

@(private="file")
rune_at_line_col :: proc(text: string, line, col: int) -> (rune, int, int) {
    // Walk to line `line` (0-based) , then `col` runes in. Return the
    // rune + its byte-start + byte-end in `text`.
    cur_line := 0
    i := 0
    for i < len(text) && cur_line < line {
        if text[i] == '\n' { cur_line += 1 }
        i += 1
    }
    // i is at start of line `line`. Now walk col runes in.
    rune_idx := 0
    for i < len(text) && rune_idx < col {
        _, sz := utf8_decode(text, i)
        if sz == 0 do break
        i += sz
        rune_idx += 1
    }
    if i >= len(text) do return 0, i, i
    r, sz := utf8_decode(text, i)
    return r, i, i + sz
}

// Extract the "identifier/glyph" starting at byte-offset `byte_start`.
// For the ASCII modal-glyphs (W! R! M? N! I> Q? P> D>), include the
// trailing punctuation. Otherwise return the single rune.
@(private="file")
hover_token_at :: proc(text: string, byte_start: int, byte_end: int) -> string {
    if byte_start >= len(text) do return ""
    // Check modal-glyph prefix : W! R! M? N! I> Q? P> D>
    if byte_start + 2 <= len(text) {
        two := text[byte_start:byte_start+2]
        switch two {
        case "W!", "R!", "M?", "N!", "I>", "Q?", "P>", "D>":
            return two
        }
    }
    return text[byte_start:byte_end]
}

@(private="file")
handle_hover :: proc(state: ^Lsp_State, params: ^J_Value, id: ^J_Value) -> ^J_Value {
    result := j_null()
    td := get_prop(params, "textDocument")
    pos := get_prop(params, "position")
    if td == nil || pos == nil do return mk_response(id, result)
    uri, _ := get_str_from(td, "uri")
    doc, ok := state.docs[uri]
    if !ok do return mk_response(id, result)

    line_v := get_prop(pos, "line")
    col_v := get_prop(pos, "character")
    if line_v == nil || col_v == nil do return mk_response(id, result)
    line := int(line_v.n_int) if line_v.n_is_int else int(line_v.n)
    col := int(col_v.n_int) if col_v.n_is_int else int(col_v.n)

    _, bs, be := rune_at_line_col(doc.text, line, col)
    tok := hover_token_at(doc.text, bs, be)
    if info, found := glyph_info(tok); found {
        result = j_obj()
        contents := j_obj()
        j_put(contents, "kind", j_str("markdown"))
        body := fmt.tprintf("**%s** (`%s`) — %s", info.glyph, info.ascii, info.meaning)
        j_put(contents, "value", j_str(body))
        j_put(result, "contents", contents)
    }
    return mk_response(id, result)
}

// ---------- completion ----------

@(private="file")
Completion_Item :: struct { label, insert, detail: string }

@(private="file")
COMPLETION_ITEMS := []Completion_Item{
    {"§ section",          "§ ",            "start a new section"},
    {"§§ subsection",      "§§ ",           "subsection (depth 2)"},
    {"§§§ sub-sub",        "§§§ ",          "sub-subsection (depth 3)"},
    {"W! MUST",            "W! ",           "hard requirement"},
    {"R! SHOULD",          "R! ",           "strong recommendation"},
    {"M? MAY",             "M? ",           "optional / discretion"},
    {"N! MUST NOT",        "N! ",           "prohibition"},
    {"I> INSIGHT",         "I> ",           "key claim / important note"},
    {"Q? QUESTION",        "Q? ",           "open question"},
    {"D> DECISION",        "D> ",           "decision needed"},
    {"→ flow",             "→",             "then / yields / maps-to"},
    {"⇒ implies",          "⇒",             "logical implication"},
    {"∀ forall",           "∀",             "universal quantifier"},
    {"∃ exists",           "∃",             "existential quantifier"},
    {"⊗ having",           "⊗",             "bahuvrihi compound (having X-Y)"},
    {"✓ confirmed",        "✓",             "evidence : confirmed"},
    {"◐ partial",          "◐",             "evidence : partial / probable"},
    {"○ pending",          "○",             "evidence : pending"},
    {"✗ failed",           "✗",             "evidence : failed / rejected"},
    {"@frame",             "@frame",        "avyayibhava : per-frame scope"},
    {"@run",               "@run",          "avyayibhava : per-run scope"},
    {"@tick",              "@tick",         "avyayibhava : per-tick scope"},
}

@(private="file")
handle_completion :: proc(state: ^Lsp_State, params: ^J_Value, id: ^J_Value) -> ^J_Value {
    items := j_arr()
    for ci in COMPLETION_ITEMS {
        it := j_obj()
        j_put(it, "label", j_str(ci.label))
        j_put(it, "insertText", j_str(ci.insert))
        j_put(it, "detail", j_str(ci.detail))
        // kind 1 = Text, 14 = Keyword, 21 = Constant. Use 14 for CSL glyphs.
        j_put(it, "kind", j_int(14))
        append(&items.arr, it)
    }
    result := j_obj()
    j_put(result, "isIncomplete", j_bool(false))
    j_put(result, "items", items)
    return mk_response(id, result)
}

// ---------- documentSymbol ----------
// Emit one SymbolInformation per top-level `§ name` or `§§ name` etc.
@(private="file")
handle_document_symbol :: proc(state: ^Lsp_State, params: ^J_Value, id: ^J_Value) -> ^J_Value {
    td := get_prop(params, "textDocument")
    if td == nil do return mk_response(id, j_arr())
    uri, _ := get_str_from(td, "uri")
    doc, ok := state.docs[uri]
    if !ok do return mk_response(id, j_arr())

    symbols := j_arr()
    // Simple text-scan for lines that begin with § (or §§, §§§).
    lines_iter := 0
    line_idx := 0
    for line_start := 0; line_start < len(doc.text); /* advanced inline */ {
        // find end-of-line
        line_end := line_start
        for line_end < len(doc.text) && doc.text[line_end] != '\n' do line_end += 1
        line := doc.text[line_start:line_end]
        trimmed := line
        // strip leading whitespace
        lead := 0
        for lead < len(trimmed) && (trimmed[lead] == ' ' || trimmed[lead] == '\t') do lead += 1
        t := trimmed[lead:]
        if len(t) > 0 && t[0] == '\xc2' && len(t) > 1 && t[1] == '\xa7' {
            // starts with § (UTF-8 0xC2 0xA7). Count depth.
            depth := 0
            j := 0
            for j + 1 < len(t) && t[j] == '\xc2' && t[j + 1] == '\xa7' {
                depth += 1
                j += 2
            }
            // skip whitespace after §s
            for j < len(t) && (t[j] == ' ' || t[j] == '\t') do j += 1
            // rest-of-line is the symbol name
            name := t[j:]
            if len(name) > 0 {
                sym := j_obj()
                j_put(sym, "name", j_str(name))
                // SymbolKind : 2 = Module, 5 = Class, 23 = Struct
                j_put(sym, "kind", j_int(5 if depth == 1 else 23))
                // range : whole line
                rng := j_obj()
                s := j_obj(); j_put(s, "line", j_int(i64(line_idx)))
                              j_put(s, "character", j_int(0))
                e := j_obj(); j_put(e, "line", j_int(i64(line_idx)))
                              j_put(e, "character", j_int(i64(len(line))))
                j_put(rng, "start", s); j_put(rng, "end", e)
                j_put(sym, "range", rng)
                // selectionRange : same as range (simpler than finding the
                // specific name span)
                sr := j_obj()
                ss := j_obj(); j_put(ss, "line", j_int(i64(line_idx)))
                               j_put(ss, "character", j_int(0))
                se := j_obj(); j_put(se, "line", j_int(i64(line_idx)))
                               j_put(se, "character", j_int(i64(len(line))))
                j_put(sr, "start", ss); j_put(sr, "end", se)
                j_put(sym, "selectionRange", sr)
                append(&symbols.arr, sym)
            }
        }
        line_idx += 1
        line_start = line_end + 1
        _ = lines_iter
    }
    return mk_response(id, symbols)
}

@(private="file")
handle_did_close :: proc(state: ^Lsp_State, params: ^J_Value) {
    td := get_prop(params, "textDocument")
    if td == nil do return
    uri, _ := get_str_from(td, "uri")
    if d, ok := state.docs[uri]; ok {
        delete(d.uri); delete(d.text); delete(d.language)
        delete_key(&state.docs, uri)
    }
}

@(private="file")
get_str_from :: proc(v: ^J_Value, key: string) -> (string, bool) {
    p := get_prop(v, key)
    if p == nil || p.kind != .String do return "", false
    return p.s, true
}

// ------------------------- main message loop -------------------------

lsp_server_main :: proc() -> int {
    state := Lsp_State{}

    for {
        body, ok := read_message()
        if !ok do break  // stdin closed

        msg, pe := json_parse(string(body))
        delete(body)
        if !pe.ok {
            // Parse error : best-effort continue.
            continue
        }

        id := get_prop(msg, "id")
        method, has_method := get_str_from(msg, "method")
        params := get_prop(msg, "params")

        if !has_method {
            // Response/notification from client ; nothing to do in MVP.
            json_free(msg)
            continue
        }

        resp : ^J_Value = nil
        switch method {
        case "initialize":
            resp = handle_initialize(&state, params, id)
        case "initialized":
            // notification ; nothing to return
        case "shutdown":
            resp = handle_shutdown(&state, id)
        case "exit":
            json_free(msg)
            if state.shutdown_requested do return 0
            return 1
        case "textDocument/didOpen":
            handle_did_open(&state, params)
        case "textDocument/didChange":
            handle_did_change(&state, params)
        case "textDocument/didClose":
            handle_did_close(&state, params)
        case "textDocument/hover":
            resp = handle_hover(&state, params, id)
        case "textDocument/completion":
            resp = handle_completion(&state, params, id)
        case "textDocument/documentSymbol":
            resp = handle_document_symbol(&state, params, id)
        case:
            // Unknown method : if it has an id, respond with error ; else ignore.
            if id != nil {
                err := j_obj()
                j_put(err, "code", j_int(-32601))  // MethodNotFound
                j_put(err, "message", j_str(fmt.tprintf("method not found: %s", method)))
                envelope := j_obj()
                j_put(envelope, "jsonrpc", j_str("2.0"))
                if id != nil do j_put(envelope, "id", clone_j(id))
                j_put(envelope, "error", err)
                body := json_emit(envelope, false, context.temp_allocator)
                write_message(body)
                json_free(envelope)
            }
        }

        if resp != nil {
            body := json_emit(resp, false, context.temp_allocator)
            write_message(body)
            json_free(resp)
        }

        json_free(msg)
    }
    return 0
}
