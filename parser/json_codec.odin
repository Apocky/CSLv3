package cslparser

// § A4 Session-14 : RFC 8259 JSON parser + emitter (bespoke Odin).
//
// I> replaces : serde_json on the LSP side (D10) ; hashlib-side json.loads
//    in Python audit path can optionally delegate here too via parser.exe
// I> scope : RFC 8259 + STD 90 compliant ; no streaming API in this pass
//            (fully-buffered parse) ; ECMA-404 subset ; no BOM support
//
// API :
//   json_parse(src : string)             -> (J_Value, J_Error)
//   json_emit (v : ^J_Value, pretty)     -> string     (allocated)
//   json_emit_compact(v : ^J_Value)      -> string
//   json_free (v : ^J_Value)             -> void
//
// CLI :
//   parser.exe --json-selftest           ← RFC vectors + round-trip
//   parser.exe --json-validate <file>    ← exit 0 if valid , 1 if not
//
// Memory : all allocations use context.allocator ; callers invoke
//   json_free to release. Arena-aware : pass context.temp_allocator if
//   the caller wants lifetime-scoped parsing.

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import "core:unicode/utf8"

// ------------------------- value tree -------------------------

J_Kind :: enum u8 {
    Null,
    Bool,
    Number,
    String,
    Array,
    Object,
}

J_Value :: struct {
    kind : J_Kind,
    b    : bool,          // for Bool
    n    : f64,           // for Number
    n_is_int : bool,      // true if the source had no '.' or 'e'
    n_int : i64,          // exact i64 value when n_is_int
    s    : string,        // for String (owned ; freed by json_free)
    arr  : [dynamic]^J_Value,
    obj_keys : [dynamic]string,     // parallel arrays keep insertion order
    obj_vals : [dynamic]^J_Value,
}

J_Error :: struct {
    ok     : bool,
    msg    : string,       // static ; not freed
    pos    : int,          // byte offset
    line   : int,          // 1-indexed
    col    : int,          // 1-indexed
}

// ------------------------- parser -------------------------

@(private="file")
J_Parser :: struct {
    src : string,
    idx : int,
    line : int,
    col  : int,
}

@(private="file")
peek :: proc(p: ^J_Parser) -> u8 {
    if p.idx >= len(p.src) do return 0
    return p.src[p.idx]
}

@(private="file")
advance :: proc(p: ^J_Parser) -> u8 {
    if p.idx >= len(p.src) do return 0
    c := p.src[p.idx]
    p.idx += 1
    if c == '\n' { p.line += 1; p.col = 1 }
    else { p.col += 1 }
    return c
}

@(private="file")
skip_ws :: proc(p: ^J_Parser) {
    for p.idx < len(p.src) {
        c := p.src[p.idx]
        if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
            advance(p)
        } else {
            break
        }
    }
}

@(private="file")
err :: proc(p: ^J_Parser, msg: string) -> J_Error {
    return J_Error{ ok = false, msg = msg, pos = p.idx, line = p.line, col = p.col }
}

json_parse :: proc(src: string, allocator := context.allocator) -> (^J_Value, J_Error) {
    context.allocator = allocator
    p := J_Parser{ src = src, idx = 0, line = 1, col = 1 }
    skip_ws(&p)
    v, e := parse_value(&p)
    if !e.ok do return nil, e
    skip_ws(&p)
    if p.idx != len(p.src) {
        json_free(v)
        return nil, err(&p, "trailing content after top-level value")
    }
    return v, J_Error{ ok = true }
}

@(private="file")
parse_value :: proc(p: ^J_Parser) -> (^J_Value, J_Error) {
    skip_ws(p)
    c := peek(p)
    switch c {
    case '{': return parse_object(p)
    case '[': return parse_array(p)
    case '"': return parse_string_value(p)
    case 't', 'f': return parse_bool(p)
    case 'n': return parse_null(p)
    case '-', '0'..='9': return parse_number(p)
    case 0: return nil, err(p, "unexpected end of input")
    }
    return nil, err(p, "unexpected token")
}

@(private="file")
parse_null :: proc(p: ^J_Parser) -> (^J_Value, J_Error) {
    if p.idx + 4 > len(p.src) || p.src[p.idx:p.idx+4] != "null" {
        return nil, err(p, "expected 'null'")
    }
    for _ in 0..<4 do advance(p)
    v := new(J_Value)
    v.kind = .Null
    return v, J_Error{ ok = true }
}

@(private="file")
parse_bool :: proc(p: ^J_Parser) -> (^J_Value, J_Error) {
    if p.idx + 4 <= len(p.src) && p.src[p.idx:p.idx+4] == "true" {
        for _ in 0..<4 do advance(p)
        v := new(J_Value)
        v.kind = .Bool
        v.b = true
        return v, J_Error{ ok = true }
    }
    if p.idx + 5 <= len(p.src) && p.src[p.idx:p.idx+5] == "false" {
        for _ in 0..<5 do advance(p)
        v := new(J_Value)
        v.kind = .Bool
        v.b = false
        return v, J_Error{ ok = true }
    }
    return nil, err(p, "expected 'true' or 'false'")
}

@(private="file")
parse_number :: proc(p: ^J_Parser) -> (^J_Value, J_Error) {
    start := p.idx
    has_dot := false
    has_exp := false
    if peek(p) == '-' do advance(p)
    c0 := peek(p)
    if c0 == '0' {
        advance(p)
    } else if c0 >= '1' && c0 <= '9' {
        for {
            c := peek(p)
            if c < '0' || c > '9' do break
            advance(p)
        }
    } else {
        return nil, err(p, "invalid number (expected digit)")
    }
    if peek(p) == '.' {
        has_dot = true
        advance(p)
        has_digit := false
        for {
            c := peek(p)
            if c < '0' || c > '9' do break
            advance(p); has_digit = true
        }
        if !has_digit do return nil, err(p, "invalid number (expected digit after '.')")
    }
    if peek(p) == 'e' || peek(p) == 'E' {
        has_exp = true
        advance(p)
        if peek(p) == '+' || peek(p) == '-' do advance(p)
        has_digit := false
        for {
            c := peek(p)
            if c < '0' || c > '9' do break
            advance(p); has_digit = true
        }
        if !has_digit do return nil, err(p, "invalid number (expected digit in exponent)")
    }
    lit := p.src[start:p.idx]
    v := new(J_Value)
    v.kind = .Number
    if !has_dot && !has_exp {
        // integer-looking
        ival, ok := strconv.parse_i64(lit)
        if ok {
            v.n = f64(ival)
            v.n_is_int = true
            v.n_int = ival
            return v, J_Error{ ok = true }
        }
    }
    fval, ok := strconv.parse_f64(lit)
    if !ok do return nil, err(p, "number out of range")
    v.n = fval
    v.n_is_int = false
    return v, J_Error{ ok = true }
}

@(private="file")
parse_string_raw :: proc(p: ^J_Parser) -> (string, J_Error) {
    // Consumes leading " , returns decoded string contents, consumes trailing ".
    if advance(p) != '"' do return "", err(p, "expected '\"'")
    sb := strings.builder_make()
    for {
        if p.idx >= len(p.src) {
            strings.builder_destroy(&sb)
            return "", err(p, "unterminated string")
        }
        c := p.src[p.idx]
        if c == '"' { advance(p); break }
        if c < 0x20 {
            strings.builder_destroy(&sb)
            return "", err(p, "control character in string")
        }
        if c == '\\' {
            advance(p)
            esc := advance(p)
            switch esc {
            case '"':  strings.write_byte(&sb, '"')
            case '\\': strings.write_byte(&sb, '\\')
            case '/':  strings.write_byte(&sb, '/')
            case 'b':  strings.write_byte(&sb, '\b')
            case 'f':  strings.write_byte(&sb, '\f')
            case 'n':  strings.write_byte(&sb, '\n')
            case 'r':  strings.write_byte(&sb, '\r')
            case 't':  strings.write_byte(&sb, '\t')
            case 'u':
                cp, e := parse_unicode_escape(p)
                if !e.ok {
                    strings.builder_destroy(&sb)
                    return "", e
                }
                // Surrogate pair detection ; RFC 8259 §7.
                if cp >= 0xD800 && cp <= 0xDBFF {
                    // expect \uLLLL
                    if p.idx + 2 > len(p.src) || p.src[p.idx] != '\\' || p.src[p.idx+1] != 'u' {
                        strings.builder_destroy(&sb)
                        return "", err(p, "lone high surrogate")
                    }
                    advance(p); advance(p)
                    low, e2 := parse_unicode_escape(p)
                    if !e2.ok {
                        strings.builder_destroy(&sb)
                        return "", e2
                    }
                    if low < 0xDC00 || low > 0xDFFF {
                        strings.builder_destroy(&sb)
                        return "", err(p, "invalid low surrogate")
                    }
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00)
                }
                buf, n := utf8.encode_rune(rune(cp))
                for i in 0..<n do strings.write_byte(&sb, buf[i])
            case:
                strings.builder_destroy(&sb)
                return "", err(p, "unknown escape")
            }
        } else {
            strings.write_byte(&sb, c)
            advance(p)
        }
    }
    return strings.to_string(sb), J_Error{ ok = true }
}

@(private="file")
parse_unicode_escape :: proc(p: ^J_Parser) -> (int, J_Error) {
    if p.idx + 4 > len(p.src) do return 0, err(p, "incomplete \\uXXXX")
    v := 0
    for _ in 0..<4 {
        c := advance(p)
        d := 0
        switch {
        case c >= '0' && c <= '9': d = int(c - '0')
        case c >= 'a' && c <= 'f': d = int(c - 'a') + 10
        case c >= 'A' && c <= 'F': d = int(c - 'A') + 10
        case:
            return 0, err(p, "bad hex digit in \\u escape")
        }
        v = v * 16 + d
    }
    return v, J_Error{ ok = true }
}

@(private="file")
parse_string_value :: proc(p: ^J_Parser) -> (^J_Value, J_Error) {
    s, e := parse_string_raw(p)
    if !e.ok do return nil, e
    v := new(J_Value)
    v.kind = .String
    v.s = s
    return v, J_Error{ ok = true }
}

@(private="file")
parse_array :: proc(p: ^J_Parser) -> (^J_Value, J_Error) {
    if advance(p) != '[' do return nil, err(p, "expected '['")
    v := new(J_Value)
    v.kind = .Array
    skip_ws(p)
    if peek(p) == ']' { advance(p); return v, J_Error{ ok = true } }
    for {
        skip_ws(p)
        elem, e := parse_value(p)
        if !e.ok {
            json_free(v)
            return nil, e
        }
        append(&v.arr, elem)
        skip_ws(p)
        c := peek(p)
        if c == ',' { advance(p); continue }
        if c == ']' { advance(p); break }
        json_free(v)
        return nil, err(p, "expected ',' or ']' in array")
    }
    return v, J_Error{ ok = true }
}

@(private="file")
parse_object :: proc(p: ^J_Parser) -> (^J_Value, J_Error) {
    if advance(p) != '{' do return nil, err(p, "expected '{'")
    v := new(J_Value)
    v.kind = .Object
    skip_ws(p)
    if peek(p) == '}' { advance(p); return v, J_Error{ ok = true } }
    for {
        skip_ws(p)
        if peek(p) != '"' {
            json_free(v)
            return nil, err(p, "expected string key")
        }
        key, ke := parse_string_raw(p)
        if !ke.ok {
            json_free(v)
            return nil, ke
        }
        skip_ws(p)
        if advance(p) != ':' {
            json_free(v)
            return nil, err(p, "expected ':' after key")
        }
        skip_ws(p)
        val, ve := parse_value(p)
        if !ve.ok {
            json_free(v)
            return nil, ve
        }
        append(&v.obj_keys, key)
        append(&v.obj_vals, val)
        skip_ws(p)
        c := peek(p)
        if c == ',' { advance(p); continue }
        if c == '}' { advance(p); break }
        json_free(v)
        return nil, err(p, "expected ',' or '}' in object")
    }
    return v, J_Error{ ok = true }
}

// ------------------------- emitter -------------------------

json_emit :: proc(v: ^J_Value, pretty: bool = false,
                  allocator := context.allocator) -> string {
    context.allocator = allocator
    sb := strings.builder_make()
    emit_val(&sb, v, pretty, 0)
    return strings.to_string(sb)
}

json_emit_compact :: proc(v: ^J_Value, allocator := context.allocator) -> string {
    return json_emit(v, false, allocator)
}

@(private="file")
emit_indent :: proc(sb: ^strings.Builder, depth: int) {
    for _ in 0..<depth do strings.write_string(sb, "  ")
}

@(private="file")
emit_val :: proc(sb: ^strings.Builder, v: ^J_Value, pretty: bool, depth: int) {
    if v == nil {
        strings.write_string(sb, "null")
        return
    }
    switch v.kind {
    case .Null: strings.write_string(sb, "null")
    case .Bool: strings.write_string(sb, "true" if v.b else "false")
    case .Number:
        if v.n_is_int {
            buf: [32]u8
            s := strconv.write_int(buf[:], v.n_int, 10)
            strings.write_string(sb, s)
        } else {
            buf: [64]u8
            s := strconv.write_float(buf[:], v.n, 'g', 17, 64)
            // Odin's write_float may prefix with '+' for positive numbers ;
            // JSON spec disallows leading +, strip it.
            if len(s) > 0 && s[0] == '+' do s = s[1:]
            strings.write_string(sb, s)
        }
    case .String: emit_string(sb, v.s)
    case .Array:
        if len(v.arr) == 0 { strings.write_string(sb, "[]"); return }
        strings.write_byte(sb, '[')
        for e, i in v.arr {
            if i > 0 do strings.write_byte(sb, ',')
            if pretty {
                strings.write_byte(sb, '\n')
                emit_indent(sb, depth + 1)
            }
            emit_val(sb, e, pretty, depth + 1)
        }
        if pretty {
            strings.write_byte(sb, '\n')
            emit_indent(sb, depth)
        }
        strings.write_byte(sb, ']')
    case .Object:
        if len(v.obj_keys) == 0 { strings.write_string(sb, "{}"); return }
        strings.write_byte(sb, '{')
        for k, i in v.obj_keys {
            if i > 0 do strings.write_byte(sb, ',')
            if pretty {
                strings.write_byte(sb, '\n')
                emit_indent(sb, depth + 1)
            }
            emit_string(sb, k)
            strings.write_byte(sb, ':')
            if pretty do strings.write_byte(sb, ' ')
            emit_val(sb, v.obj_vals[i], pretty, depth + 1)
        }
        if pretty {
            strings.write_byte(sb, '\n')
            emit_indent(sb, depth)
        }
        strings.write_byte(sb, '}')
    }
}

@(private="file")
emit_string :: proc(sb: ^strings.Builder, s: string) {
    strings.write_byte(sb, '"')
    for i in 0..<len(s) {
        c := s[i]
        switch c {
        case '"':  strings.write_string(sb, "\\\"")
        case '\\': strings.write_string(sb, "\\\\")
        case '\b': strings.write_string(sb, "\\b")
        case '\f': strings.write_string(sb, "\\f")
        case '\n': strings.write_string(sb, "\\n")
        case '\r': strings.write_string(sb, "\\r")
        case '\t': strings.write_string(sb, "\\t")
        case:
            if c < 0x20 {
                buf: [8]u8
                buf[0] = '\\'; buf[1] = 'u'; buf[2] = '0'; buf[3] = '0'
                HEX := "0123456789abcdef"
                buf[4] = HEX[(c >> 4) & 0xf]
                buf[5] = HEX[c & 0xf]
                strings.write_bytes(sb, buf[:6])
            } else {
                strings.write_byte(sb, c)
            }
        }
    }
    strings.write_byte(sb, '"')
}

// ------------------------- cleanup -------------------------

json_free :: proc(v: ^J_Value) {
    if v == nil do return
    switch v.kind {
    case .Null, .Bool, .Number:
    case .String:
        delete(v.s)
    case .Array:
        for e in v.arr do json_free(e)
        delete(v.arr)
    case .Object:
        for k in v.obj_keys do delete(k)
        for e in v.obj_vals do json_free(e)
        delete(v.obj_keys)
        delete(v.obj_vals)
    }
    free(v)
}

// ------------------------- selftest -------------------------

// Covers : RFC 8259 §3-§8 constructs ; round-trip equality ;
// UTF-8 + unicode escape ; nested structures ; numbers.
json_selftest :: proc() {
    ok, fail := 0, 0

    vec :: struct { name, json: string }
    vectors := []vec{
        { "empty-obj", "{}" },
        { "empty-arr", "[]" },
        { "null",      "null" },
        { "bool-t",    "true" },
        { "bool-f",    "false" },
        { "int",       "42" },
        { "negint",    "-17" },
        { "float",     "3.14" },
        { "exp",       "1e9" },
        { "string",    `"hello"` },
        { "escapes",   `"a\"b\\c\nd\tf"` },
        { "unicode",   `"\u00e9"` },
        { "surrogate", `"\uD83D\uDE00"` },
        { "nested", `{"a":[1,2,{"b":null,"c":true}],"d":"x"}` },
    }
    for v in vectors {
        val, e := json_parse(v.json, context.temp_allocator)
        if !e.ok {
            fmt.printf("%-14s parse-FAIL (%s @ L%d C%d)\n", v.name, e.msg, e.line, e.col)
            fail += 1
            continue
        }
        // Round-trip : emit + re-parse + shallow equality check.
        emitted := json_emit(val, false, context.temp_allocator)
        val2, e2 := json_parse(emitted, context.temp_allocator)
        if !e2.ok {
            fmt.printf("%-14s round-trip FAIL (re-parse: %s)\n", v.name, e2.msg)
            fail += 1
            continue
        }
        if !values_eq(val, val2) {
            fmt.printf("%-14s round-trip FAIL (values diff)\n  %s\n", v.name, emitted)
            fail += 1
            continue
        }
        fmt.printf("%-14s OK\n", v.name)
        ok += 1
    }

    // Failure cases (must ERROR) :
    bad := []vec{
        { "trailing-comma-obj", `{"a":1,}` },
        { "trailing-comma-arr", `[1,2,]` },
        { "bare-word",          `yes` },
        { "unclosed-string",    `"abc` },
        { "lone-surrogate",     `"\uD83D"` },
        { "leading-zero",       `01` },
    }
    for v in bad {
        _, e := json_parse(v.json, context.temp_allocator)
        if e.ok {
            fmt.printf("%-20s reject-FAIL (accepted)\n", v.name)
            fail += 1
        } else {
            fmt.printf("%-20s rejected OK\n", v.name)
            ok += 1
        }
    }

    fmt.printf("§ JSON selftest : %d ok , %d failed\n", ok, fail)
    if fail > 0 do os.exit(1)
    os.exit(0)
}

@(private="file")
values_eq :: proc(a, b: ^J_Value) -> bool {
    if a == nil && b == nil do return true
    if a == nil || b == nil do return false
    if a.kind != b.kind do return false
    switch a.kind {
    case .Null: return true
    case .Bool: return a.b == b.b
    case .Number:
        if a.n_is_int && b.n_is_int do return a.n_int == b.n_int
        return a.n == b.n
    case .String: return a.s == b.s
    case .Array:
        if len(a.arr) != len(b.arr) do return false
        for i in 0..<len(a.arr) do if !values_eq(a.arr[i], b.arr[i]) do return false
        return true
    case .Object:
        if len(a.obj_keys) != len(b.obj_keys) do return false
        for i in 0..<len(a.obj_keys) {
            if a.obj_keys[i] != b.obj_keys[i] do return false
            if !values_eq(a.obj_vals[i], b.obj_vals[i]) do return false
        }
        return true
    }
    return false
}
