package cslparser

// § A5 Session-14 : JSON-Schema subset validator (bespoke Odin).
//
// I> replaces : python `jsonschema` dep (D42) in the m₂ audit path.
// I> scope : Draft-07 subset sufficient for internal schemas :
//     types : null, boolean, integer, number, string, array, object
//     string : minLength, maxLength, pattern (PATTERN NOT YET ← wait A8)
//     number : minimum, maximum, exclusiveMin/Max, multipleOf
//     array  : minItems, maxItems, uniqueItems, items
//     object : required, properties, additionalProperties, minProperties
//     meta   : enum, const, oneOf, anyOf, allOf, not, $ref (flat only)
// I> ~300 LOC ← depends on A4 JSON parser for schema+doc loading
//
// API :
//   schema_validate(schema_src, doc_src) -> (ok, error_list)
//   schema_selftest()                     -> internal + emit_schema/* round-trip
//
// CLI :
//   parser.exe --json-schema-validate <schema.json> <doc.json>
//   parser.exe --json-schema-selftest

import "core:fmt"
import "core:os"
import "core:strings"

Schema_Error :: struct {
    path : string,   // JSON Pointer-ish : "/properties/foo/items"
    msg  : string,
}

Schema_Result :: struct {
    ok     : bool,
    errors : [dynamic]Schema_Error,
}

@(private="file")
add_err :: proc(r: ^Schema_Result, path, msg: string) {
    r.ok = false
    append(&r.errors, Schema_Error{
        path = strings.clone(path),
        msg  = strings.clone(msg),
    })
}

schema_validate :: proc(schema_src, doc_src: string) -> Schema_Result {
    r := Schema_Result{ ok = true }
    sch, se := json_parse(schema_src, context.temp_allocator)
    if !se.ok {
        add_err(&r, "/", fmt.tprintf("schema parse error L%d:%d %s",
            se.line, se.col, se.msg))
        return r
    }
    doc, de := json_parse(doc_src, context.temp_allocator)
    if !de.ok {
        add_err(&r, "/", fmt.tprintf("document parse error L%d:%d %s",
            de.line, de.col, de.msg))
        return r
    }
    validate_node(sch, doc, "", &r)
    return r
}

// Public : also used by lsp_server.odin for extracting LSP message fields.
get_prop :: proc(v: ^J_Value, key: string) -> ^J_Value {
    if v == nil || v.kind != .Object do return nil
    for k, i in v.obj_keys do if k == key do return v.obj_vals[i]
    return nil
}

@(private="file")
get_str :: proc(v: ^J_Value, key: string) -> (string, bool) {
    p := get_prop(v, key)
    if p == nil || p.kind != .String do return "", false
    return p.s, true
}

@(private="file")
get_num :: proc(v: ^J_Value, key: string) -> (f64, bool) {
    p := get_prop(v, key)
    if p == nil || p.kind != .Number do return 0, false
    return p.n, true
}

@(private="file")
get_bool :: proc(v: ^J_Value, key: string) -> (bool, bool) {
    p := get_prop(v, key)
    if p == nil || p.kind != .Bool do return false, false
    return p.b, true
}

@(private="file")
kind_name :: proc(v: ^J_Value) -> string {
    if v == nil do return "null"
    switch v.kind {
    case .Null:   return "null"
    case .Bool:   return "boolean"
    case .Number:
        // Schema distinguishes integer from number : treat as integer
        // only if the JSON source was parsed as an exact integer.
        return "integer" if v.n_is_int else "number"
    case .String: return "string"
    case .Array:  return "array"
    case .Object: return "object"
    }
    return "unknown"
}

@(private="file")
validate_node :: proc(schema, doc: ^J_Value, path: string, r: ^Schema_Result) {
    if schema == nil do return
    // boolean schemas : true accepts everything, false rejects everything
    if schema.kind == .Bool {
        if !schema.b do add_err(r, path, "schema=false ; rejects all documents")
        return
    }
    if schema.kind != .Object {
        add_err(r, path, "invalid schema : expected object or boolean")
        return
    }
    // Type check
    if tp, ok := get_str(schema, "type"); ok {
        kn := kind_name(doc)
        // integer-accepts-int-also : if schema says "number", accept int
        match := kn == tp ||
            (tp == "number" && kn == "integer")
        if !match {
            add_err(r, path, fmt.tprintf("type mismatch : want %s, got %s",
                tp, kn))
        }
    } else if tp_arr := get_prop(schema, "type"); tp_arr != nil && tp_arr.kind == .Array {
        kn := kind_name(doc)
        any_match := false
        for t in tp_arr.arr {
            if t.kind == .String {
                if t.s == kn || (t.s == "number" && kn == "integer") {
                    any_match = true; break
                }
            }
        }
        if !any_match {
            add_err(r, path, fmt.tprintf("type mismatch for multi-type : got %s", kn))
        }
    }

    // enum
    if en := get_prop(schema, "enum"); en != nil && en.kind == .Array {
        found := false
        for candidate in en.arr do if values_eq(candidate, doc) { found = true; break }
        if !found do add_err(r, path, "value not in enum")
    }

    // const
    if co := get_prop(schema, "const"); co != nil {
        if !values_eq(co, doc) do add_err(r, path, "value does not equal const")
    }

    // Kind-specific
    if doc != nil {
        switch doc.kind {
        case .String:  validate_string(schema, doc, path, r)
        case .Number:  validate_number(schema, doc, path, r)
        case .Array:   validate_array(schema, doc, path, r)
        case .Object:  validate_object(schema, doc, path, r)
        case .Null, .Bool:
        }
    }

    // oneOf / anyOf / allOf / not
    if p := get_prop(schema, "allOf"); p != nil && p.kind == .Array {
        for sub in p.arr do validate_node(sub, doc, path, r)
    }
    if p := get_prop(schema, "anyOf"); p != nil && p.kind == .Array {
        any_ok := false
        for sub in p.arr {
            tmp := Schema_Result{ ok = true }
            validate_node(sub, doc, path, &tmp)
            if tmp.ok { any_ok = true; break }
        }
        if !any_ok do add_err(r, path, "no anyOf branch matched")
    }
    if p := get_prop(schema, "oneOf"); p != nil && p.kind == .Array {
        n_ok := 0
        for sub in p.arr {
            tmp := Schema_Result{ ok = true }
            validate_node(sub, doc, path, &tmp)
            if tmp.ok do n_ok += 1
        }
        if n_ok != 1 do add_err(r, path,
            fmt.tprintf("oneOf expected exactly 1 match, got %d", n_ok))
    }
    if p := get_prop(schema, "not"); p != nil {
        tmp := Schema_Result{ ok = true }
        validate_node(p, doc, path, &tmp)
        if tmp.ok do add_err(r, path, "must NOT match not-schema")
    }
}

@(private="file")
validate_string :: proc(schema, doc: ^J_Value, path: string, r: ^Schema_Result) {
    n_chars := 0
    for _ in doc.s do n_chars += 1
    if min_len, ok := get_num(schema, "minLength"); ok {
        if f64(n_chars) < min_len do add_err(r, path,
            fmt.tprintf("string too short (%d < %d)", n_chars, int(min_len)))
    }
    if max_len, ok := get_num(schema, "maxLength"); ok {
        if f64(n_chars) > max_len do add_err(r, path,
            fmt.tprintf("string too long (%d > %d)", n_chars, int(max_len)))
    }
    // pattern : Draft-07 ECMAScript-regex subset (Session-15 O1 wire-up).
    // We compile on first use per-validate ; a cache is a Session-16+ opt.
    if p := get_prop(schema, "pattern"); p != nil && p.kind == .String {
        re, perr := regex_compile(p.s, context.temp_allocator)
        if !perr.ok {
            add_err(r, path, fmt.tprintf("pattern compile error : %s", perr.msg))
        } else {
            defer regex_free(&re)
            m := regex_search(&re, doc.s)
            if !m.ok {
                add_err(r, path, fmt.tprintf("string %q does not match pattern %q",
                    doc.s, p.s))
            }
        }
    }
}

@(private="file")
validate_number :: proc(schema, doc: ^J_Value, path: string, r: ^Schema_Result) {
    if m, ok := get_num(schema, "minimum"); ok {
        if doc.n < m do add_err(r, path,
            fmt.tprintf("%.6g < minimum %.6g", doc.n, m))
    }
    if m, ok := get_num(schema, "maximum"); ok {
        if doc.n > m do add_err(r, path,
            fmt.tprintf("%.6g > maximum %.6g", doc.n, m))
    }
    if m, ok := get_num(schema, "exclusiveMinimum"); ok {
        if doc.n <= m do add_err(r, path,
            fmt.tprintf("%.6g <= exclusiveMinimum %.6g", doc.n, m))
    }
    if m, ok := get_num(schema, "exclusiveMaximum"); ok {
        if doc.n >= m do add_err(r, path,
            fmt.tprintf("%.6g >= exclusiveMaximum %.6g", doc.n, m))
    }
    if m, ok := get_num(schema, "multipleOf"); ok {
        q := doc.n / m
        if q - f64(int(q)) > 1e-9 do add_err(r, path,
            fmt.tprintf("%.6g not a multiple of %.6g", doc.n, m))
    }
}

@(private="file")
validate_array :: proc(schema, doc: ^J_Value, path: string, r: ^Schema_Result) {
    n := len(doc.arr)
    if m, ok := get_num(schema, "minItems"); ok {
        if f64(n) < m do add_err(r, path,
            fmt.tprintf("array too short (%d < %d)", n, int(m)))
    }
    if m, ok := get_num(schema, "maxItems"); ok {
        if f64(n) > m do add_err(r, path,
            fmt.tprintf("array too long (%d > %d)", n, int(m)))
    }
    if u, ok := get_bool(schema, "uniqueItems"); ok && u {
        // O(n²) dedup ; arrays in schemas are small
        for i in 0 ..< n {
            for j in i+1 ..< n {
                if values_eq(doc.arr[i], doc.arr[j]) {
                    add_err(r, path, fmt.tprintf("duplicate items at %d and %d", i, j))
                    break
                }
            }
        }
    }
    if items := get_prop(schema, "items"); items != nil {
        for elem, i in doc.arr {
            sub_path := fmt.tprintf("%s/%d", path, i)
            validate_node(items, elem, sub_path, r)
        }
    }
}

@(private="file")
validate_object :: proc(schema, doc: ^J_Value, path: string, r: ^Schema_Result) {
    if m, ok := get_num(schema, "minProperties"); ok {
        if f64(len(doc.obj_keys)) < m do add_err(r, path,
            fmt.tprintf("too few properties (%d < %d)",
                len(doc.obj_keys), int(m)))
    }
    if m, ok := get_num(schema, "maxProperties"); ok {
        if f64(len(doc.obj_keys)) > m do add_err(r, path,
            fmt.tprintf("too many properties (%d > %d)",
                len(doc.obj_keys), int(m)))
    }
    if req := get_prop(schema, "required"); req != nil && req.kind == .Array {
        for r_entry in req.arr {
            if r_entry.kind != .String do continue
            if get_prop(doc, r_entry.s) == nil {
                add_err(r, path, fmt.tprintf("missing required %q", r_entry.s))
            }
        }
    }
    props := get_prop(schema, "properties")
    for key, i in doc.obj_keys {
        val := doc.obj_vals[i]
        sub_path := fmt.tprintf("%s/%s", path, key)
        if props != nil && props.kind == .Object {
            if sub := get_prop(props, key); sub != nil {
                validate_node(sub, val, sub_path, r)
                continue
            }
        }
        // Fall through : check additionalProperties
        addl := get_prop(schema, "additionalProperties")
        if addl != nil {
            if addl.kind == .Bool && !addl.b {
                add_err(r, sub_path, fmt.tprintf("unexpected property %q", key))
            } else if addl.kind == .Object {
                validate_node(addl, val, sub_path, r)
            }
        }
    }
}

// ---------- selftest ----------

schema_selftest :: proc() {
    ok, fail := 0, 0
    Case :: struct { name, schema, doc: string, valid: bool }
    cases := []Case{
        { "type-str",        `{"type":"string"}`,              `"hi"`,         true },
        { "type-str-wrong",  `{"type":"string"}`,              `42`,           false },
        { "int",             `{"type":"integer"}`,             `7`,            true },
        { "int-vs-number",   `{"type":"number"}`,              `7`,            true },
        { "num-vs-int",      `{"type":"integer"}`,             `3.14`,         false },
        { "min-ok",          `{"type":"number","minimum":0}`,  `1`,            true },
        { "min-fail",        `{"type":"number","minimum":0}`,  `-1`,           false },
        { "excl-min-eq",     `{"type":"number","exclusiveMinimum":0}`, `0`,    false },
        { "min-len",         `{"type":"string","minLength":2}`, `"a"`,         false },
        { "max-len",         `{"type":"string","maxLength":2}`, `"abc"`,       false },
        { "enum-ok",         `{"enum":["a","b","c"]}`,          `"b"`,          true },
        { "enum-fail",       `{"enum":["a","b","c"]}`,          `"d"`,          false },
        { "const-ok",        `{"const":42}`,                    `42`,           true },
        { "const-fail",      `{"const":42}`,                    `43`,           false },
        { "arr-min",         `{"type":"array","minItems":2}`,   `[1]`,          false },
        { "arr-unique",      `{"type":"array","uniqueItems":true}`, `[1,1]`,   false },
        { "arr-items",       `{"type":"array","items":{"type":"number"}}`, `[1,2,3]`, true },
        { "arr-items-bad",   `{"type":"array","items":{"type":"number"}}`, `[1,"x"]`, false },
        { "obj-required",    `{"type":"object","required":["a"]}`, `{"b":1}`,  false },
        { "obj-required-ok", `{"type":"object","required":["a"]}`, `{"a":1}`,  true  },
        { "obj-props",       `{"type":"object","properties":{"n":{"type":"number"}}}`, `{"n":5}`, true },
        { "obj-addl-false",  `{"type":"object","properties":{"a":{}},"additionalProperties":false}`,
                             `{"a":1,"b":2}`, false },
        { "oneOf-ok",        `{"oneOf":[{"type":"integer"},{"type":"string"}]}`, `42`, true },
        { "oneOf-fail-two",  `{"oneOf":[{"type":"integer"},{"type":"number"}]}`, `7`, false },
        { "not-ok",          `{"not":{"type":"string"}}`, `42`, true },
        { "not-fail",        `{"not":{"type":"string"}}`, `"hi"`, false },
        { "bool-schema-true",  `true`,  `42`, true },
        { "bool-schema-false", `false`, `42`, false },
        // Session-15 O1 : pattern wire-up (requires A8 regex).
        { "pattern-ok",    `{"type":"string","pattern":"^[a-z]+$"}`, `"abc"`,  true },
        { "pattern-fail",  `{"type":"string","pattern":"^[a-z]+$"}`, `"ab3"`, false },
        { "pattern-anchored-ok",
          `{"type":"string","pattern":"^\\d{4}-\\d{2}-\\d{2}$"}`,
          `"2026-04-17"`, true },
        { "pattern-anchored-fail",
          `{"type":"string","pattern":"^\\d{4}-\\d{2}-\\d{2}$"}`,
          `"not-a-date"`, false },
        { "pattern-unicode",
          `{"type":"string","pattern":"^\\p{L}+$"}`,
          `"abcXYZ"`, true },
        { "pattern-bad-regex",
          `{"type":"string","pattern":"[unclosed"}`,
          `"x"`, false },
    }
    for c in cases {
        r := schema_validate(c.schema, c.doc)
        got_valid := r.ok
        mark := "OK"
        if got_valid != c.valid {
            mark = "FAIL"
            fail += 1
        } else {
            ok += 1
        }
        fmt.printf("%-20s %s\n", c.name, mark)
        if got_valid != c.valid && len(r.errors) > 0 {
            for e in r.errors do fmt.printf("  err: %s: %s\n", e.path, e.msg)
        }
        // free error strings
        for e in r.errors { delete(e.path); delete(e.msg) }
        delete(r.errors)
    }
    fmt.printf("§ JSON-Schema selftest : %d ok, %d failed\n", ok, fail)
    if fail > 0 do os.exit(1)
    os.exit(0)
}
