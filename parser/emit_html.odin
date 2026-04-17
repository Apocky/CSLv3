package cslparser

// § CSLv3 EMIT-HTML BACKEND (T28.3 Session-10)
// I> semantic HTML5 ; <section> per-§ ; <code class="csl-<kind>"> per-token
// I> standalone (full <html> + <head>) or fragment (body-only) mode
// I> CSS taxonomy : emit_schema/html-v1.css
// I> TOC sidebar when standalone ; clickable cross-refs via id-anchors

import "core:fmt"
import "core:strings"

HTML_CSS_TEXT :: `/* CSLv3 HTML Emit — CSS Taxonomy (html-v1) */
:root {
  --bg:        #0f0f14;
  --fg:        #e0e0e6;
  --keyword:   #c6c;
  --morpheme:  #6cc;
  --operator:  #fc6;
  --modal:     #f8a;
  --evidence:  #9c6;
  --glyph:     #ff8;
  --type:      #8cf;
  --string:    #caa;
  --number:    #a8d;
  --comment:   #666;
}
body.cslv3 { background: var(--bg); color: var(--fg); font-family: "JetBrains Mono", "Fira Code", monospace; }
h1, h2, h3 { color: var(--glyph); }
.csl-section { border-left: 3px solid var(--keyword); padding-left: 1em; margin: 1em 0; }
.csl-morpheme { color: var(--morpheme); font-weight: 600; }
.csl-modal    { color: var(--modal);    font-weight: 600; }
.csl-evidence { color: var(--evidence); }
.csl-glyph    { color: var(--glyph);    }
.csl-operator { color: var(--operator); }
.csl-type     { color: var(--type);     }
.csl-string   { color: var(--string);   }
.csl-number   { color: var(--number);   }
.csl-comment  { color: var(--comment);  font-style: italic; }
.csl-keyword  { color: var(--keyword);  font-weight: 600; }
pre.csl-block { background: rgba(255,255,255,0.03); padding: 1em; overflow-x: auto; border-radius: 4px; }
nav.csl-toc   { position: sticky; top: 1em; }
nav.csl-toc a { color: var(--glyph); text-decoration: none; }
nav.csl-toc a:hover { text-decoration: underline; }
`

emit_html :: proc(ctx: ^Emit_Context) -> string {
    sb := strings.builder_make()
    standalone := ctx.config.standalone

    if standalone {
        strings.write_string(&sb, "<!DOCTYPE html>\n")
        strings.write_string(&sb, "<!-- schema: html-v1 -->\n")
        strings.write_string(&sb, "<html lang=\"en\">\n<head>\n")
        strings.write_string(&sb, "  <meta charset=\"utf-8\">\n")
        strings.write_string(&sb, fmt.tprintf("  <title>%s — CSLv3</title>\n",
            html_escape(derive_title_html(ctx.source_file))))
        strings.write_string(&sb, "  <style>\n")
        strings.write_string(&sb, HTML_CSS_TEXT)
        strings.write_string(&sb, "\n  </style>\n</head>\n<body class=\"cslv3\">\n")
    }

    // Header + TOC
    title := derive_title_html(ctx.source_file)
    strings.write_string(&sb, fmt.tprintf("  <h1>%s</h1>\n", html_escape(title)))

    if standalone && ctx.ast_root != nil {
        emit_toc(&sb, ctx.ast_root)
    }

    strings.write_string(&sb, "  <main>\n")
    if ctx.ast_root != nil {
        for c in ctx.ast_root.children {
            emit_html_node(&sb, c, 2)
        }
    } else {
        // fallback : syntax-highlighted source block
        emit_highlighted_block(&sb, ctx.source_text)
    }
    strings.write_string(&sb, "  </main>\n")

    if standalone {
        strings.write_string(&sb, "</body>\n</html>\n")
    }
    return strings.to_string(sb)
}

@(private="file")
derive_title_html :: proc(path: string) -> string {
    last_slash := strings.last_index_any(path, "/\\")
    stem := path if last_slash < 0 else path[last_slash+1:]
    if dot := strings.last_index(stem, "."); dot > 0 do stem = stem[:dot]
    return stem
}

@(private="file")
emit_toc :: proc(sb: ^strings.Builder, root: ^Node) {
    strings.write_string(sb, "  <nav class=\"csl-toc\">\n    <h2>Contents</h2>\n    <ul>\n")
    collect_toc(sb, root)
    strings.write_string(sb, "    </ul>\n  </nav>\n")
}

@(private="file")
collect_toc :: proc(sb: ^strings.Builder, n: ^Node) {
    if n == nil do return
    if n.kind == .Section {
        a := html_anchor(n.text)
        strings.write_string(sb, fmt.tprintf(
            "      <li><a href=\"#%s\">%s</a></li>\n",
            a, html_escape(n.text)))
    }
    for c in n.children do collect_toc(sb, c)
}

@(private="file")
emit_html_node :: proc(sb: ^strings.Builder, n: ^Node, level: int) {
    if n == nil do return
    #partial switch n.kind {
    case .Section:
        a := html_anchor(n.text)
        h := fmt.tprintf("h%d", min(level, 6))
        strings.write_string(sb, "  <section class=\"csl-section\">\n")
        strings.write_string(sb, fmt.tprintf(
            "    <%s id=\"%s\">%s</%s>\n", h, a, html_escape(n.text), h))
        for c in n.children do emit_html_node(sb, c, level + 1)
        strings.write_string(sb, "  </section>\n")
    case .Comment:
        strings.write_string(sb, fmt.tprintf(
            "    <p class=\"csl-comment\"># %s</p>\n", html_escape(n.text)))
    case .Document:
        for c in n.children do emit_html_node(sb, c, level)
    case:
        emit_def_as_html(sb, n)
    }
}

@(private="file")
emit_def_as_html :: proc(sb: ^strings.Builder, n: ^Node) {
    csb := strings.builder_make(context.temp_allocator)
    pprint_doc_with_mode(n, &csb, .Canonical)
    s := strings.trim_space(strings.to_string(csb))
    if len(s) == 0 do return
    strings.write_string(sb, "    <pre class=\"csl-block\">")
    emit_highlighted_inline(sb, s)
    strings.write_string(sb, "</pre>\n")
}

@(private="file")
emit_highlighted_block :: proc(sb: ^strings.Builder, src: string) {
    strings.write_string(sb, "    <pre class=\"csl-block\">")
    emit_highlighted_inline(sb, src)
    strings.write_string(sb, "</pre>\n")
}

// Tiny hand-rolled highlighter : wraps characters in <span class="csl-...">
// based on kind-categories used in semantic_tokens.
@(private="file")
emit_highlighted_inline :: proc(sb: ^strings.Builder, text: string) {
    chars: []rune = cast([]rune)([]rune{})   // placeholder
    // decode utf-8 char-by-char
    i := 0
    for i < len(text) {
        c, size := decode_rune_at(text, i)
        cls := classify_char(c)
        if cls == "" {
            strings.write_rune(sb, c)
        } else {
            strings.write_string(sb, fmt.tprintf("<span class=\"csl-%s\">", cls))
            html_escape_rune(sb, c)
            strings.write_string(sb, "</span>")
        }
        _ = chars
        i += size
    }
}

@(private="file")
classify_char :: proc(c: rune) -> string {
    switch c {
    case '§', '¶': return "section"
    case '→', '←', '↔', '≤', '≥', '≠', '∧', '∨', '¬', '∀', '∃', '∈', '⊆', '⊂',
         '∪', '∩', '⇒', '∵', '∴', '⊗', '⊕', '⊑', '⊔', '⊓', '∫', '⊞':
        return "glyph"
    case '⟨', '⟩', '⌈', '⌉', '⟦', '⟧', '«', '»', '⟪', '⟫':
        return "operator"
    case '✓', '✗', '◐', '○', '⊘', '△', '▽', '‼':
        return "evidence"
    case '.', '+', '-', '@', ':', '=':
        return "operator"
    }
    if c >= '0' && c <= '9' do return "number"
    return ""
}

@(private="file")
html_escape :: proc(s: string) -> string {
    sb := strings.builder_make(context.temp_allocator)
    for c in s {
        switch c {
        case '<': strings.write_string(&sb, "&lt;")
        case '>': strings.write_string(&sb, "&gt;")
        case '&': strings.write_string(&sb, "&amp;")
        case '"': strings.write_string(&sb, "&quot;")
        case '\'': strings.write_string(&sb, "&#39;")
        case:    strings.write_rune(&sb, c)
        }
    }
    return strings.to_string(sb)
}

@(private="file")
html_escape_rune :: proc(sb: ^strings.Builder, c: rune) {
    switch c {
    case '<':  strings.write_string(sb, "&lt;")
    case '>':  strings.write_string(sb, "&gt;")
    case '&':  strings.write_string(sb, "&amp;")
    case '"':  strings.write_string(sb, "&quot;")
    case '\'': strings.write_string(sb, "&#39;")
    case:      strings.write_rune(sb, c)
    }
}

@(private="file")
html_anchor :: proc(s: string) -> string {
    sb := strings.builder_make(context.temp_allocator)
    for c in s {
        if c >= 'A' && c <= 'Z' do strings.write_rune(&sb, c + 32)
        else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' do strings.write_rune(&sb, c)
        else if c == ' ' || c == '_' do strings.write_byte(&sb, '-')
    }
    return strings.to_string(sb)
}

// utf-8 decode : Odin core has `utf8.decode_rune_in_string` ; use it.
@(private="file")
decode_rune_at :: proc(s: string, i: int) -> (rune, int) {
    if i >= len(s) do return 0, 0
    // simplistic ASCII-first path
    b := s[i]
    if b < 0x80 do return rune(b), 1
    // delegate to stdlib utf8 for non-ASCII
    sub := s[i:]
    if len(sub) == 0 do return 0, 1
    r: rune
    size: int
    when true {
        // fallback : iterate runes from the substring and take the first
        for c in sub {
            r = c
            size = utf8_byte_len(c)
            break
        }
    }
    if size == 0 do size = 1
    return r, size
}

@(private="file")
utf8_byte_len :: proc(r: rune) -> int {
    n := u32(r)
    if n <= 0x7F do return 1
    if n <= 0x7FF do return 2
    if n <= 0xFFFF do return 3
    return 4
}
