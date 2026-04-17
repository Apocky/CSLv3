package cslparser

// § CSLv3 IR JSON SERIALIZER (T21.e Session-6)
// I> machine-readable JSON for CSSLv3-tooling-consumption + golden-diff
// I> schema :
//    {
//      "module": "<source-file>",
//      "ops": [ <op> ]
//    }
//    <op> = {
//      "id": N, "name": "cslv3.fn", "pos": {"line": L, "col": C, "byte": B},
//      "operands": [%N, …], "results": [ {"id": N, "name":"x", "ty":"i32"}, … ],
//      "attrs":    { "name": {...attr...}, … },
//      "regions":  [ <region> ]
//    }
//    <region> = { "kind": "Fn_Body", "blocks": [ <block> ] }
//    <block>  = { "id": N, "label": "entry", "args": [...values], "ops": [ <op> ] }
//    <attr>   = { "kind": "Int"|"Float"|"Str"|"Bool"|"Symbol"|"Type"|"Label", "value": ... }
// I> indent : 2-space (line-oriented) — easy diffable golden files
// R! ← matches cssllint JSON schema style (type_repr for types)

import "core:fmt"
import "core:slice"
import "core:strings"

// ---------- Public entry ----------

ir_json_module :: proc(m: ^Module) -> string {
    sb := strings.builder_make()
    j_module(&sb, m, 0)
    strings.write_byte(&sb, '\n')
    return strings.to_string(sb)
}

// ---------- helpers ----------

@(private="file")
indent :: proc(sb: ^strings.Builder, n: int) {
    for _ in 0..<n do strings.write_string(sb, "  ")
}

@(private="file")
j_str :: proc(sb: ^strings.Builder, s: string) {
    strings.write_byte(sb, '"')
    for c in s {
        switch c {
        case '"':  strings.write_string(sb, "\\\"")
        case '\\': strings.write_string(sb, "\\\\")
        case '\n': strings.write_string(sb, "\\n")
        case '\r': strings.write_string(sb, "\\r")
        case '\t': strings.write_string(sb, "\\t")
        case:
            if c < 0x20 do strings.write_string(sb, fmt.tprintf("\\u%04x", i32(c)))
            else do strings.write_rune(sb, c)
        }
    }
    strings.write_byte(sb, '"')
}

// ---------- Module ----------

@(private="file")
j_module :: proc(sb: ^strings.Builder, m: ^Module, d: int) {
    if m == nil {
        strings.write_string(sb, "{\"module\":null,\"ops\":[]}")
        return
    }
    strings.write_string(sb, "{\n")
    indent(sb, d + 1) ; strings.write_string(sb, "\"module\": ")
    j_str(sb, m.source_file)
    strings.write_string(sb, ",\n")
    indent(sb, d + 1) ; strings.write_string(sb, "\"ops\": ")
    j_op_list(sb, m.ops[:], d + 1)
    strings.write_byte(sb, '\n')
    indent(sb, d) ; strings.write_byte(sb, '}')
}

// ---------- Ops ----------

@(private="file")
j_op_list :: proc(sb: ^strings.Builder, ops: []^Op, d: int) {
    if len(ops) == 0 {
        strings.write_string(sb, "[]")
        return
    }
    strings.write_string(sb, "[\n")
    for op, i in ops {
        indent(sb, d + 1)
        j_op(sb, op, d + 1)
        if i < len(ops) - 1 do strings.write_byte(sb, ',')
        strings.write_byte(sb, '\n')
    }
    indent(sb, d) ; strings.write_byte(sb, ']')
}

@(private="file")
j_op :: proc(sb: ^strings.Builder, op: ^Op, d: int) {
    if op == nil {
        strings.write_string(sb, "null")
        return
    }
    strings.write_string(sb, "{\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"id\": ")
    strings.write_string(sb, fmt.tprintf("%d", op.id))
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"name\": ")
    j_str(sb, op.name)
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"pos\": ")
    j_pos(sb, op.loc)
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"operands\": ")
    j_value_refs(sb, op.operands[:])
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"results\": ")
    j_value_defs(sb, op.results[:], d + 1)
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"attrs\": ")
    j_attrs(sb, op.attrs, d + 1)
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"regions\": ")
    j_region_list(sb, op.regions[:], d + 1)
    strings.write_byte(sb, '\n')

    indent(sb, d) ; strings.write_byte(sb, '}')
}

// ---------- Regions / Blocks ----------

@(private="file")
j_region_list :: proc(sb: ^strings.Builder, regs: []^Region, d: int) {
    if len(regs) == 0 {
        strings.write_string(sb, "[]")
        return
    }
    strings.write_string(sb, "[\n")
    for r, i in regs {
        indent(sb, d + 1)
        j_region(sb, r, d + 1)
        if i < len(regs) - 1 do strings.write_byte(sb, ',')
        strings.write_byte(sb, '\n')
    }
    indent(sb, d) ; strings.write_byte(sb, ']')
}

@(private="file")
j_region :: proc(sb: ^strings.Builder, r: ^Region, d: int) {
    if r == nil {
        strings.write_string(sb, "null")
        return
    }
    strings.write_string(sb, "{\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"kind\": ")
    j_str(sb, fmt.tprintf("%v", r.kind))
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"blocks\": ")
    j_block_list(sb, r.blocks[:], d + 1)
    strings.write_byte(sb, '\n')

    indent(sb, d) ; strings.write_byte(sb, '}')
}

@(private="file")
j_block_list :: proc(sb: ^strings.Builder, bs: []^Block, d: int) {
    if len(bs) == 0 {
        strings.write_string(sb, "[]")
        return
    }
    strings.write_string(sb, "[\n")
    for b, i in bs {
        indent(sb, d + 1)
        j_block(sb, b, d + 1)
        if i < len(bs) - 1 do strings.write_byte(sb, ',')
        strings.write_byte(sb, '\n')
    }
    indent(sb, d) ; strings.write_byte(sb, ']')
}

@(private="file")
j_block :: proc(sb: ^strings.Builder, b: ^Block, d: int) {
    if b == nil {
        strings.write_string(sb, "null")
        return
    }
    strings.write_string(sb, "{\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"id\": ")
    strings.write_string(sb, fmt.tprintf("%d", b.id))
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"label\": ")
    j_str(sb, b.label)
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"args\": ")
    j_value_defs(sb, b.args[:], d + 1)
    strings.write_string(sb, ",\n")

    indent(sb, d + 1) ; strings.write_string(sb, "\"ops\": ")
    j_op_list(sb, b.ops[:], d + 1)
    strings.write_byte(sb, '\n')

    indent(sb, d) ; strings.write_byte(sb, '}')
}

// ---------- Values ----------

@(private="file")
j_value_refs :: proc(sb: ^strings.Builder, vs: []^Value) {
    strings.write_byte(sb, '[')
    for v, i in vs {
        if i > 0 do strings.write_string(sb, ", ")
        if v == nil {
            strings.write_string(sb, "null")
        } else {
            strings.write_string(sb, fmt.tprintf("%d", v.id))
        }
    }
    strings.write_byte(sb, ']')
}

@(private="file")
j_value_defs :: proc(sb: ^strings.Builder, vs: []^Value, d: int) {
    if len(vs) == 0 {
        strings.write_string(sb, "[]")
        return
    }
    strings.write_string(sb, "[\n")
    for v, i in vs {
        indent(sb, d + 1)
        j_value_def(sb, v)
        if i < len(vs) - 1 do strings.write_byte(sb, ',')
        strings.write_byte(sb, '\n')
    }
    indent(sb, d) ; strings.write_byte(sb, ']')
}

@(private="file")
j_value_def :: proc(sb: ^strings.Builder, v: ^Value) {
    if v == nil {
        strings.write_string(sb, "null")
        return
    }
    strings.write_byte(sb, '{')
    strings.write_string(sb, "\"id\": ")
    strings.write_string(sb, fmt.tprintf("%d", v.id))
    strings.write_string(sb, ", \"name\": ")
    j_str(sb, v.name)
    strings.write_string(sb, ", \"ty\": ")
    j_str(sb, type_repr(v.ty))
    strings.write_string(sb, ", \"kind\": ")
    j_str(sb, fmt.tprintf("%v", v.def_kind))
    strings.write_byte(sb, '}')
}

// ---------- Attrs ----------

@(private="file")
j_attrs :: proc(sb: ^strings.Builder, m: map[string]Attr, d: int) {
    if len(m) == 0 {
        strings.write_string(sb, "{}")
        return
    }
    // Sorted key-order for determinism
    keys := make([dynamic]string, 0, len(m))
    defer delete(keys)
    for k in m do append(&keys, k)
    slice.sort(keys[:])

    strings.write_string(sb, "{\n")
    for k, i in keys {
        indent(sb, d + 1)
        j_str(sb, k)
        strings.write_string(sb, ": ")
        j_attr(sb, m[k])
        if i < len(keys) - 1 do strings.write_byte(sb, ',')
        strings.write_byte(sb, '\n')
    }
    indent(sb, d) ; strings.write_byte(sb, '}')
}

@(private="file")
j_attr :: proc(sb: ^strings.Builder, a: Attr) {
    strings.write_byte(sb, '{')
    strings.write_string(sb, "\"kind\": ")
    j_str(sb, fmt.tprintf("%v", a.kind))
    strings.write_string(sb, ", \"value\": ")
    switch a.kind {
    case .Int:
        strings.write_string(sb, fmt.tprintf("%d", a.int_v))
    case .Float:
        strings.write_string(sb, fmt.tprintf("%g", a.float_v))
    case .Bool:
        strings.write_string(sb, a.bool_v ? "true" : "false")
    case .Str, .Symbol, .Label, .Sig:
        j_str(sb, a.str_v)
    case .Type:
        j_str(sb, type_repr(a.ty_v))
    }
    strings.write_byte(sb, '}')
}

// ---------- Source_Pos ----------

@(private="file")
j_pos :: proc(sb: ^strings.Builder, p: Source_Pos) {
    strings.write_string(sb, fmt.tprintf("{{\"line\": %d, \"col\": %d, \"byte\": %d}}",
                                          p.line, p.col, p.offset))
}
