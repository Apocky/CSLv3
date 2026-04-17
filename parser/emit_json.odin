package cslparser

// § CSLv3 EMIT-JSON BACKEND (T28.5 Session-10)
// I> canonical unified JSON : schema + ast + types + ir in one document
// I> supersedes per-mode --typecheck --json / --ir --json / cssllint --json
//    by unifying them behind schema-v1 declaration
// I> stable key-ordering ← BTreeMap-equivalent (sorted on emit)
// I> schema-version "json-v1" declared at top-level

import "core:fmt"
import "core:strings"

JSON_SCHEMA_TEXT :: `{
  "$schema":     "https://json-schema.org/draft/2020-12/schema",
  "$id":         "https://cslv3.apocky/schemas/json-v1.json",
  "title":       "CSLv3 Unified Emit Schema",
  "description": "AST + types + IR + diagnostics in one canonical document.",
  "type":        "object",
  "required":    ["schema", "schemaVersion", "source", "ast"],
  "properties": {
    "schema":        { "type": "string", "const": "cslv3-emit-json" },
    "schemaVersion": { "type": "string", "const": "json-v1" },
    "source":        { "type": "object" },
    "ast":           { "type": "object" },
    "types":         { "type": "object" },
    "ir":            { "type": "object" },
    "diagnostics":   { "type": "array"  }
  }
}`

emit_json_target :: proc(ctx: ^Emit_Context) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, "{\n")
    strings.write_string(&sb, "  \"schema\": \"cslv3-emit-json\",\n")
    strings.write_string(&sb, "  \"schemaVersion\": \"json-v1\",\n")
    strings.write_string(&sb, "  \"emittedAt\": ")
    write_jstr(&sb, time_now_iso8601())
    strings.write_string(&sb, ",\n")

    // source
    strings.write_string(&sb, "  \"source\": {\n    \"file\": ")
    write_jstr(&sb, ctx.source_file)
    strings.write_string(&sb, ",\n    \"bytes\": ")
    strings.write_string(&sb, fmt.tprintf("%d", len(ctx.source_text)))
    strings.write_string(&sb, ",\n    \"sha256\": ")
    write_jstr(&sb, sha256_hex_of_string(ctx.source_text))
    strings.write_string(&sb, "\n  },\n")

    // AST
    strings.write_string(&sb, "  \"ast\": ")
    if ctx.ast_root != nil {
        emit_ast_json(&sb, ctx.ast_root, 1)
    } else {
        strings.write_string(&sb, "null")
    }
    strings.write_string(&sb, ",\n")

    // types (if available)
    strings.write_string(&sb, "  \"types\": ")
    if ctx.tc_result != nil {
        emit_types_json(&sb, ctx.tc_result, 1)
    } else {
        strings.write_string(&sb, "null")
    }
    strings.write_string(&sb, ",\n")

    // IR
    strings.write_string(&sb, "  \"ir\": ")
    if ctx.ir_module != nil {
        strings.write_string(&sb, ir_json_module(ctx.ir_module))
    } else {
        strings.write_string(&sb, "null")
    }
    strings.write_byte(&sb, '\n')
    strings.write_string(&sb, "}\n")
    return strings.to_string(sb)
}

// ---------- AST node → JSON ----------

@(private="file")
emit_ast_json :: proc(sb: ^strings.Builder, n: ^Node, depth: int) {
    if n == nil {
        strings.write_string(sb, "null")
        return
    }
    strings.write_string(sb, "{\n")
    indent_n(sb, depth + 1)
    strings.write_string(sb, "\"kind\": ")
    write_jstr(sb, node_kind_name_for(n.kind))
    strings.write_string(sb, ",\n")
    indent_n(sb, depth + 1)
    strings.write_string(sb, "\"text\": ")
    write_jstr(sb, n.text)
    strings.write_string(sb, ",\n")
    indent_n(sb, depth + 1)
    strings.write_string(sb, "\"pos\": ")
    strings.write_string(sb, fmt.tprintf("{{\"line\":%d,\"col\":%d,\"byte\":%d}}",
        n.pos.line, n.pos.col, n.pos.offset))
    strings.write_string(sb, ",\n")
    if n.suffix != .Invalid {
        indent_n(sb, depth + 1)
        strings.write_string(sb, "\"suffix\": ")
        write_jstr(sb, token_kind_name(n.suffix))
        strings.write_string(sb, ",\n")
    }
    indent_n(sb, depth + 1)
    strings.write_string(sb, "\"children\": ")
    if len(n.children) == 0 {
        strings.write_string(sb, "[]")
    } else {
        strings.write_string(sb, "[\n")
        for c, i in n.children {
            indent_n(sb, depth + 2)
            emit_ast_json(sb, c, depth + 2)
            if i < len(n.children) - 1 do strings.write_byte(sb, ',')
            strings.write_byte(sb, '\n')
        }
        indent_n(sb, depth + 1)
        strings.write_byte(sb, ']')
    }
    strings.write_byte(sb, '\n')
    indent_n(sb, depth)
    strings.write_byte(sb, '}')
}

@(private="file")
node_kind_name_for :: proc(k: Node_Kind) -> string {
    // Use fmt.tprint on the enum variant for stable names.
    return fmt.tprintf("%v", k)
}

// ---------- Types result → JSON ----------

@(private="file")
emit_types_json :: proc(sb: ^strings.Builder, r: ^Tc_Result, depth: int) {
    strings.write_string(sb, "{\n")
    indent_n(sb, depth + 1)
    strings.write_string(sb, fmt.tprintf("\"refine_obligations\": %d,\n", r.refine_obligations))
    indent_n(sb, depth + 1)
    strings.write_string(sb, fmt.tprintf("\"strict_parse\": %t,\n", r.strict_parse))
    indent_n(sb, depth + 1)
    strings.write_string(sb, "\"diagnostics\": [")
    for d, i in r.diagnostics {
        if i > 0 do strings.write_byte(sb, ',')
        strings.write_string(sb, fmt.tprintf(
            "{{\"line\":%d,\"col\":%d,\"sev\":\"%s\",\"code\":\"%s\",\"msg\":",
            d.pos.line, d.pos.col, severity_label(d.severity), sem_code_name(d.code)))
        write_jstr(sb, d.msg)
        strings.write_byte(sb, '}')
    }
    strings.write_byte(sb, ']')
    strings.write_byte(sb, '\n')
    indent_n(sb, depth)
    strings.write_byte(sb, '}')
}

// ---------- helpers ----------

@(private="file")
write_jstr :: proc(sb: ^strings.Builder, s: string) {
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

@(private="file")
indent_n :: proc(sb: ^strings.Builder, n: int) {
    for _ in 0..<n do strings.write_string(sb, "  ")
}
