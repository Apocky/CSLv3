package cslparser

// § CSLv3 EMIT SOURCE-MAP (T28.a Session-10)
// I> v3 sourcemap skeleton (JSON) ; per-target segment-level precision M?
// I> sidecar .map file ; line/col preserved through emission
// I> reverse-lookup (rendered-position → original) enables round-trip-verify
// I> consumers : browsers + debuggers + diff-tools

import "core:fmt"
import "core:strings"

Source_Segment :: struct {
    generated_line:   int,
    generated_col:    int,
    source_idx:       int,   // index into sources array
    original_line:    int,
    original_col:     int,
    name_idx:         int,   // -1 if no name
}

Source_Map_Builder :: struct {
    sources:  [dynamic]string,
    names:    [dynamic]string,
    segments: [dynamic]Source_Segment,
    source_file: string,
}

smb_init :: proc(b: ^Source_Map_Builder, source_file: string) {
    b.sources = make([dynamic]string)
    b.names = make([dynamic]string)
    b.segments = make([dynamic]Source_Segment)
    b.source_file = source_file
    append(&b.sources, source_file)
}

smb_destroy :: proc(b: ^Source_Map_Builder) {
    delete(b.sources)
    delete(b.names)
    delete(b.segments)
}

smb_record :: proc(b: ^Source_Map_Builder, gen_line, gen_col, orig_line, orig_col: int, name: string = "") {
    name_idx := -1
    if len(name) > 0 {
        name_idx = len(b.names)
        append(&b.names, strings.clone(name))
    }
    append(&b.segments, Source_Segment{
        generated_line = gen_line,
        generated_col  = gen_col,
        source_idx     = 0,
        original_line  = orig_line,
        original_col   = orig_col,
        name_idx       = name_idx,
    })
}

// Produce v3-sourcemap JSON. For simplicity we emit the textual position-
// list directly rather than VLQ-encoded mappings. Tools that require VLQ
// (browser devtools) will need an intermediate transformer. LSP/pandoc
// consumers consume the raw positions directly.

smb_to_v3 :: proc(b: ^Source_Map_Builder) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, "{\n")
    strings.write_string(&sb, "  \"version\": 3,\n")
    strings.write_string(&sb, "  \"file\": ")
    write_str_json(&sb, b.source_file)
    strings.write_string(&sb, ",\n  \"sources\": [")
    for s, i in b.sources {
        if i > 0 do strings.write_byte(&sb, ',')
        write_str_json(&sb, s)
    }
    strings.write_string(&sb, "],\n  \"names\": [")
    for n, i in b.names {
        if i > 0 do strings.write_byte(&sb, ',')
        write_str_json(&sb, n)
    }
    strings.write_string(&sb, "],\n  \"segments\": [\n")
    for seg, i in b.segments {
        if i > 0 do strings.write_string(&sb, ",\n")
        strings.write_string(&sb, fmt.tprintf(
            "    {{\"genLine\":%d,\"genCol\":%d,\"srcLine\":%d,\"srcCol\":%d,\"name\":%d}}",
            seg.generated_line, seg.generated_col,
            seg.original_line, seg.original_col, seg.name_idx,
        ))
    }
    strings.write_string(&sb, "\n  ]\n}\n")
    return strings.to_string(sb)
}

@(private="file")
write_str_json :: proc(sb: ^strings.Builder, s: string) {
    strings.write_byte(sb, '"')
    for c in s {
        switch c {
        case '"':  strings.write_string(sb, "\\\"")
        case '\\': strings.write_string(sb, "\\\\")
        case '\n': strings.write_string(sb, "\\n")
        case:      strings.write_rune(sb, c)
        }
    }
    strings.write_byte(sb, '"')
}

// ---------- Default source-map for an Emit_Context ----------
// Targets that don't populate per-segment maps fall back to one segment per
// top-level AST-node. It's not precise but it preserves round-trip ability.

source_map_v3 :: proc(ctx: ^Emit_Context) -> string {
    b: Source_Map_Builder
    smb_init(&b, ctx.source_file)
    defer smb_destroy(&b)

    if ctx.ast_root != nil {
        collect_ast_positions(ctx.ast_root, &b, 0)
    }
    return smb_to_v3(&b)
}

@(private="file")
collect_ast_positions :: proc(n: ^Node, b: ^Source_Map_Builder, gen_line: int) {
    if n == nil do return
    smb_record(b, gen_line, 0, n.pos.line, n.pos.col, n.text)
    line := gen_line + 1
    for c in n.children {
        collect_ast_positions(c, b, line)
        line += 1
    }
}
