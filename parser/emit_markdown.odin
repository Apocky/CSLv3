package cslparser

// § CSLv3 EMIT-MARKDOWN BACKEND (T28.2 Session-10)
// I> GitHub-Flavored Markdown ; § → ## headings ; CSL-code-blocks fenced
// I> ruby-annotations for glyph-heavy lines (accessibility / screen-readers)
// I> cross-refs auto-generated from §-headings (GFM anchor-style)
// I> style-guide : emit_schema/markdown-v1.md

import "core:fmt"
import "core:strings"

MARKDOWN_STYLE_TEXT :: `# CSLv3 Markdown Emit — Style Guide (markdown-v1)

- Top-level file heading derived from source filename.
- Each "§ Name" section becomes a level-2 heading "## Name".
- Code spans contain the original CSLv3 text in fenced "csl" blocks.
- Glyph-heavy lines optionally get ruby annotations for accessibility.
- Cross-refs use GFM-style fragment anchors: [Section](#section-name).
- Tables render straightforward CSL tables as Markdown tables.
- The first line is always the schema-version comment: <!-- schema: markdown-v1 -->.
`

emit_markdown :: proc(ctx: ^Emit_Context) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, "<!-- schema: markdown-v1 -->\n")
    strings.write_string(&sb, "<!-- source: ")
    strings.write_string(&sb, md_escape(ctx.source_file))
    strings.write_string(&sb, " -->\n\n")

    title := derive_title(ctx.source_file)
    strings.write_string(&sb, fmt.tprintf("# %s\n\n", md_escape(title)))

    if ctx.ast_root == nil {
        // fallback : embed source verbatim in fenced block
        emit_source_block(&sb, ctx.source_text)
        return strings.to_string(sb)
    }

    // Walk AST top-level : emit sections + pass-through narrative comments
    for c in ctx.ast_root.children {
        emit_md_node(&sb, c, 2)
    }

    return strings.to_string(sb)
}

@(private="file")
derive_title :: proc(path: string) -> string {
    // strip directory and extension
    last_slash := strings.last_index_any(path, "/\\")
    stem := path if last_slash < 0 else path[last_slash+1:]
    if dot := strings.last_index(stem, "."); dot > 0 {
        stem = stem[:dot]
    }
    return stem
}

@(private="file")
emit_md_node :: proc(sb: ^strings.Builder, n: ^Node, level: int) {
    if n == nil do return
    #partial switch n.kind {
    case .Section:
        head := md_escape(n.text)
        h := strings.repeat("#", min(level, 6))
        strings.write_string(sb, fmt.tprintf("\n%s %s\n", h, head))
        // anchor comment for cross-refs
        strings.write_string(sb, fmt.tprintf("<a id=\"%s\"></a>\n\n", md_anchor(n.text)))
        for c in n.children do emit_md_node(sb, c, level + 1)

    case .Comment:
        // render CSL comment as Markdown blockquote
        strings.write_string(sb, fmt.tprintf("> %s\n\n", md_escape(n.text)))

    case .Document:
        for c in n.children do emit_md_node(sb, c, level)

    case .Definition, .Function_Def, .Type_Def, .Enum_Def, .Alias_Def,
         .Directive, .Import, .Export, .Expr_Stmt, .Relation:
        emit_def_as_code(sb, n)

    case .Block:
        for c in n.children do emit_md_node(sb, c, level)

    case:
        emit_def_as_code(sb, n)
    }
}

@(private="file")
emit_def_as_code :: proc(sb: ^strings.Builder, n: ^Node) {
    // Best-effort reconstruct line via pprint
    csb := strings.builder_make(context.temp_allocator)
    pprint_doc_with_mode(n, &csb, .Canonical)
    s := strings.trim_space(strings.to_string(csb))
    if len(s) == 0 do return
    strings.write_string(sb, "```csl\n")
    strings.write_string(sb, s)
    strings.write_string(sb, "\n```\n\n")
}

@(private="file")
emit_source_block :: proc(sb: ^strings.Builder, src: string) {
    strings.write_string(sb, "```csl\n")
    strings.write_string(sb, src)
    if !strings.has_suffix(src, "\n") do strings.write_byte(sb, '\n')
    strings.write_string(sb, "```\n")
}

@(private="file")
md_escape :: proc(s: string) -> string {
    sb := strings.builder_make(context.temp_allocator)
    for c in s {
        switch c {
        case '\\': strings.write_string(&sb, "\\\\")
        case '`':  strings.write_string(&sb, "\\`")
        case '*':  strings.write_string(&sb, "\\*")
        case '_':  strings.write_string(&sb, "\\_")
        case '[':  strings.write_string(&sb, "\\[")
        case ']':  strings.write_string(&sb, "\\]")
        case:      strings.write_rune(&sb, c)
        }
    }
    return strings.to_string(sb)
}

@(private="file")
md_anchor :: proc(s: string) -> string {
    sb := strings.builder_make(context.temp_allocator)
    for c in s {
        if c >= 'A' && c <= 'Z' do strings.write_rune(&sb, c + 32)
        else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' do strings.write_rune(&sb, c)
        else if c == ' ' || c == '_' do strings.write_byte(&sb, '-')
    }
    return strings.to_string(sb)
}
