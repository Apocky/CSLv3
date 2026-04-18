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
