package cslparser

// § CSLv3 PRETTY-PRINTER (round-trip) + MODES (T12)
// I> walks AST → emits CSLv3 source
// W! round-trip: parse(src) → AST → print(AST) → reparse ≡ original-AST (shape)
// R! comments NOT preserved (lexer drops them by default)
// R! exact whitespace NOT preserved (indent is regenerated per mode)

import "core:fmt"
import "core:strings"

Print_Mode :: enum {
    Canonical,    // default: 2-space indent, unicode preserved
    Compact,      // 1-space indent, no blank lines between top-level sections
    Literate,     // 4-space indent, blank line between every section
    AsciiOnly,    // every glyph rendered via its ASCII alias
    UnicodeOnly,  // same as Canonical (unicode is already the preferred form)
}

// Package-level mode flag — set by pprint_doc_with_mode.
@(private="file")
g_print_mode: Print_Mode = .Canonical

// entry points
pprint_doc :: proc(n: ^Node, sb: ^strings.Builder) {
    if n == nil do return
    g_print_mode = .Canonical
    pprint_node(n, sb, 0)
}

pprint_doc_with_mode :: proc(n: ^Node, sb: ^strings.Builder, mode: Print_Mode) {
    if n == nil do return
    g_print_mode = mode
    pprint_node(n, sb, 0)
}

@(private="file")
indent_width :: proc() -> int {
    switch g_print_mode {
    case .Compact:                    return 1
    case .Literate:                   return 4
    case .Canonical, .AsciiOnly, .UnicodeOnly:
                                      return 2
    }
    return 2
}

@(private="file")
indent_to :: proc(sb: ^strings.Builder, depth: int) {
    for _ in 0 ..< (depth * indent_width()) do strings.write_rune(sb, ' ')
}

// render a token kind respecting the current Print_Mode.  In AsciiOnly mode,
// unicode glyphs are replaced by their ASCII aliases where documented in
// specs/12_TOKENIZER.csl.  In other modes, use the canonical (unicode) form.
@(private="file")
render_token :: proc(k: Token_Kind) -> string {
    if g_print_mode == .AsciiOnly {
        #partial switch k {
        case .Arrow_Right:     return "->"
        case .Arrow_Left:      return "<-"
        case .Arrow_Bidi:      return "<->"
        case .Implies:         return "=>"
        case .Entails:         return "|-"
        case .Therefore:       return ".:."
        case .Because:         return ":.."
        case .QED:             return "QED"
        case .ForAll:          return "all"
        case .Exists:          return "any"
        case .In:              return "in"
        case .NotIn:           return "!in"
        case .Union:           return "|+"
        case .Intersect:       return "&+"
        case .Subset:          return "<:"
        case .Superset:        return ":>"
        case .Not:             return "~"
        case .And:             return "&&"
        case .Or:              return "||"
        case .Xor:             return "xor"
        case .Tensor:          return "x*"
        case .Identical:       return "==="
        case .Approx:          return "~="
        case .Gte:             return ">="
        case .Lte:             return "<="
        case .Infinity:        return "inf"
        case .Empty:           return "nil"
        case .Ev_Confirmed:    return "[x]"
        case .Ev_Partial:      return "[~]"
        case .Ev_Pending:      return "[ ]"
        case .Ev_Failed:       return "[!]"
        case .Ev_Unknown:      return "[?]"
        case .Ev_Hypothetical: return "[^]"
        case .Ev_Deprecated:   return "[v]"
        case .Ev_Proven:       return "[!!]"
        case .Section:         return "S:"
        }
    }
    return token_kind_name(k)
}

// literal glyph-or-alias rendering used inline in pprint_node bodies.
@(private="file")
glyph :: proc(unicode, ascii: string) -> string {
    return ascii if g_print_mode == .AsciiOnly else unicode
}

@(private="file")
pprint_slot_prefix :: proc(n: ^Node, sb: ^strings.Builder) {
    if n.evidence != .Invalid {
        strings.write_string(sb, render_token(n.evidence))
        strings.write_rune(sb, ' ')
    }
    if n.modal != .Invalid {
        strings.write_string(sb, render_token(n.modal))
        strings.write_rune(sb, ' ')
    }
    if n.det != .Invalid {
        strings.write_string(sb, render_token(n.det))
    }
}

@(private="file")
pprint_suffix :: proc(n: ^Node, sb: ^strings.Builder) {
    if n.suffix != .Invalid {
        strings.write_string(sb, render_token(n.suffix))
    }
}

@(private="file")
pprint_morphemes :: proc(n: ^Node, sb: ^strings.Builder) {
    for m in n.morphemes {
        strings.write_rune(sb, '.')
        strings.write_string(sb, m)
    }
}

@(private="file")
pprint_comments_before :: proc(n: ^Node, sb: ^strings.Builder, depth: int) {
    if n == nil do return
    for c in n.comments_before {
        indent_to(sb, depth)
        // '#' is already in c if it started with '#' ; lexer captured starting-'#'.
        // emit verbatim + newline.
        strings.write_string(sb, c)
        strings.write_rune(sb, '\n')
    }
}

@(private="file")
pprint_node :: proc(n: ^Node, sb: ^strings.Builder, depth: int) {
    if n == nil do return
    pprint_comments_before(n, sb, depth)
    #partial switch n.kind {
    case .Document:
        for c, i in n.children {
            if i > 0 do strings.write_rune(sb, '\n')
            pprint_node(c, sb, depth)
        }

    case .Section:
        section_depth := int(n.int_val)
        if section_depth < 1 do section_depth = 1
        indent_to(sb, depth)
        for _ in 0 ..< section_depth do strings.write_string(sb, glyph("§", "S:"))
        strings.write_rune(sb, ' ')
        strings.write_string(sb, n.text)
        if n.evidence != .Invalid {
            strings.write_rune(sb, ' ')
            strings.write_string(sb, render_token(n.evidence))
        }
        strings.write_rune(sb, '\n')
        for c in n.children {
            pprint_node(c, sb, depth + 1)
        }

    case .Block:
        for c in n.children {
            pprint_node(c, sb, depth)
        }

    case .Definition:
        indent_to(sb, depth)
        pprint_slot_prefix(n, sb)
        if len(n.children) > 0 do pprint_node_inline(n.children[0], sb)
        if n.op == .Colon || n.op == .DoubleColon {
            strings.write_rune(sb, ' ')
            strings.write_string(sb, render_token(n.op))
            strings.write_rune(sb, ' ')
            if n.type_expr != nil do pprint_node_inline(n.type_expr, sb)
            if n.constraint != nil {
                strings.write_rune(sb, ' ')
                pprint_node_inline(n.constraint, sb)
            }
            if len(n.children) > 1 {
                strings.write_string(sb, " = ")
                pprint_node_inline(n.children[1], sb)
            }
        } else if n.op == .Eq || n.op == .Plus_Eq || n.op == .Minus_Eq || n.op == .Star_Eq || n.op == .Slash_Eq {
            strings.write_rune(sb, ' ')
            strings.write_string(sb, render_token(n.op))
            strings.write_rune(sb, ' ')
            if len(n.children) > 1 do pprint_node_inline(n.children[1], sb)
        }
        pprint_trailing(n, sb)
        strings.write_rune(sb, '\n')

    case .Relation:
        indent_to(sb, depth)
        pprint_slot_prefix(n, sb)
        if len(n.children) > 0 do pprint_node_inline(n.children[0], sb)
        strings.write_rune(sb, ' ')
        strings.write_string(sb, render_token(n.op))
        strings.write_rune(sb, ' ')
        if len(n.children) > 1 do pprint_node_inline(n.children[1], sb)
        pprint_trailing(n, sb)
        strings.write_rune(sb, '\n')

    case .Function_Def:
        indent_to(sb, depth)
        pprint_slot_prefix(n, sb)
        strings.write_string(sb, "fn ")
        strings.write_string(sb, n.text)
        pprint_suffix(n, sb)
        strings.write_rune(sb, ' ')
        // children: [params_block, body?]
        if len(n.children) > 0 {
            strings.write_rune(sb, '(')
            params := n.children[0]
            for p, i in params.children {
                if i > 0 do strings.write_string(sb, ", ")
                pprint_node_inline(p, sb)
            }
            strings.write_rune(sb, ')')
        }
        if n.type_expr != nil {
            strings.write_string(sb, " -> ")
            pprint_node_inline(n.type_expr, sb)
        }
        if len(n.children) > 1 {
            strings.write_string(sb, " = ")
            body := n.children[1]
            if body.kind == .Block && len(body.children) == 1 {
                pprint_node_inline(body.children[0], sb)
            } else {
                pprint_node_inline(body, sb)
            }
        }
        strings.write_rune(sb, '\n')

    case .Type_Def:
        indent_to(sb, depth)
        strings.write_string(sb, "def ")
        strings.write_string(sb, n.text)
        pprint_suffix(n, sb)
        if n.type_expr != nil {
            strings.write_string(sb, " = ")
            pprint_node_inline(n.type_expr, sb)
            strings.write_rune(sb, '\n')
        } else if len(n.children) > 0 {
            strings.write_string(sb, " ⟨\n")
            for c in n.children {
                indent_to(sb, depth + 1)
                pprint_node_inline(c, sb)
                strings.write_rune(sb, '\n')
            }
            indent_to(sb, depth)
            strings.write_string(sb, "⟩\n")
        } else {
            strings.write_rune(sb, '\n')
        }

    case .Enum_Def:
        indent_to(sb, depth)
        strings.write_string(sb, "def ")
        strings.write_string(sb, n.text)
        pprint_suffix(n, sb)
        strings.write_string(sb, " = enum[ ")
        for v, i in n.children {
            if i > 0 do strings.write_string(sb, ", ")
            strings.write_string(sb, v.text)
        }
        strings.write_string(sb, " ]\n")

    case .Constraint:
        indent_to(sb, depth)
        strings.write_string(sb, glyph("⌈", "[^"))
        for c in n.children do pprint_node_inline(c, sb)
        strings.write_string(sb, glyph("⌉", "^]"))
        strings.write_rune(sb, '\n')

    case .Precondition:
        indent_to(sb, depth)
        strings.write_string(sb, glyph("⌊", "[_"))
        for c in n.children do pprint_node_inline(c, sb)
        strings.write_string(sb, glyph("⌋", "_]"))
        strings.write_rune(sb, '\n')

    case .Formula:
        indent_to(sb, depth)
        strings.write_string(sb, glyph("⟦", "[["))
        strings.write_string(sb, n.text)
        strings.write_string(sb, glyph("⟧", "]]"))
        strings.write_rune(sb, '\n')

    case .Directive:
        indent_to(sb, depth)
        pprint_slot_prefix(n, sb)
        if len(n.text) > 0 {
            strings.write_string(sb, n.text)
        } else {
            for c, i in n.children {
                if i > 0 do strings.write_rune(sb, ' ')
                pprint_node_inline(c, sb)
            }
        }
        strings.write_rune(sb, '\n')

    case .Expr_Stmt:
        indent_to(sb, depth)
        pprint_slot_prefix(n, sb)
        for c, i in n.children {
            if i > 0 do strings.write_rune(sb, ' ')
            pprint_node_inline(c, sb)
        }
        if n.constraint != nil {
            strings.write_rune(sb, ' ')
            pprint_node_inline(n.constraint, sb)
        }
        pprint_trailing(n, sb)
        strings.write_rune(sb, '\n')

    case .ForAll_Stmt:
        indent_to(sb, depth)
        strings.write_string(sb, "∀ ")
        strings.write_string(sb, n.text)
        if len(n.children) > 0 {
            strings.write_string(sb, " ∈ ")
            pprint_node_inline(n.children[0], sb)
        }
        strings.write_rune(sb, ':')
        strings.write_rune(sb, '\n')
        if len(n.children) > 1 {
            b := n.children[1]
            for c in b.children do pprint_node(c, sb, depth + 1)
        }

    case .Alias_Def:
        indent_to(sb, depth)
        strings.write_string(sb, "alias ")
        strings.write_string(sb, n.text)
        strings.write_string(sb, " = ")
        if len(n.children) > 0 do pprint_node_inline(n.children[0], sb)
        strings.write_rune(sb, '\n')

    case .Import:
        indent_to(sb, depth)
        strings.write_string(sb, "use ")
        if len(n.children) > 0 do pprint_node_inline(n.children[0], sb)
        strings.write_rune(sb, '\n')

    case .Comment:
        indent_to(sb, depth)
        strings.write_rune(sb, '#')
        strings.write_string(sb, n.text)
        strings.write_rune(sb, '\n')

    case:
        // fallthrough: render as inline then newline
        indent_to(sb, depth)
        pprint_node_inline(n, sb)
        strings.write_rune(sb, '\n')
    }
}

@(private="file")
pprint_trailing :: proc(n: ^Node, sb: ^strings.Builder) {
    if n.gate != nil {
        strings.write_rune(sb, ' ')
        pprint_node_inline(n.gate, sb)
    }
    if n.scope != nil {
        strings.write_rune(sb, ' ')
        pprint_node_inline(n.scope, sb)
    }
    if len(n.meta) > 0 {
        strings.write_string(sb, " # ")
        strings.write_string(sb, n.meta)
    }
}

@(private="file")
pprint_node_inline :: proc(n: ^Node, sb: ^strings.Builder) {
    if n == nil do return
    #partial switch n.kind {
    case .Ident:
        strings.write_string(sb, n.text)
        pprint_suffix(n, sb)
        pprint_morphemes(n, sb)
    case .Num_Lit:
        if n.is_float {
            strings.write_string(sb, fmt.tprintf("%g", n.float_val))
        } else if len(n.text) > 0 {
            strings.write_string(sb, n.text)
        } else {
            strings.write_string(sb, fmt.tprintf("%d", n.int_val))
        }
    case .Str_Lit:
        strings.write_rune(sb, '"')
        strings.write_string(sb, n.text)
        strings.write_rune(sb, '"')
    case .Bool_Lit:
        strings.write_string(sb, n.bool_val ? "true" : "false")
    case .Nil_Lit:
        strings.write_string(sb, "nil")
    case .PosRef:
        strings.write_string(sb, n.text)
    case .Compound_Expr:
        if len(n.children) >= 2 {
            pprint_node_inline(n.children[0], sb)
            strings.write_string(sb, render_token(n.op))
            pprint_node_inline(n.children[1], sb)
            pprint_morphemes(n, sb)
        }
    case .Binary:
        if len(n.children) >= 2 {
            pprint_node_inline(n.children[0], sb)
            strings.write_rune(sb, ' ')
            strings.write_string(sb, render_token(n.op))
            strings.write_rune(sb, ' ')
            pprint_node_inline(n.children[1], sb)
        }
    case .Unary:
        strings.write_string(sb, render_token(n.op))
        if len(n.children) > 0 do pprint_node_inline(n.children[0], sb)
    case .Call:
        if len(n.children) > 0 {
            pprint_node_inline(n.children[0], sb)
            strings.write_rune(sb, '(')
            for i := 1; i < len(n.children); i += 1 {
                if i > 1 do strings.write_string(sb, ", ")
                pprint_node_inline(n.children[i], sb)
            }
            strings.write_rune(sb, ')')
        }
    case .Index:
        if len(n.children) >= 2 {
            pprint_node_inline(n.children[0], sb)
            strings.write_rune(sb, '[')
            pprint_node_inline(n.children[1], sb)
            strings.write_rune(sb, ']')
        }
    case .Group:
        strings.write_rune(sb, '(')
        for c in n.children do pprint_node_inline(c, sb)
        strings.write_rune(sb, ')')
    case .Tuple_Expr:
        strings.write_rune(sb, '(')
        for c, i in n.children {
            if i > 0 do strings.write_string(sb, ", ")
            pprint_node_inline(c, sb)
        }
        strings.write_rune(sb, ')')
    case .List_Expr:
        strings.write_rune(sb, '[')
        for c, i in n.children {
            if i > 0 do strings.write_string(sb, ", ")
            pprint_node_inline(c, sb)
        }
        strings.write_rune(sb, ']')
    case .Record_Expr:
        strings.write_string(sb, glyph("⟨", "<|"))
        for c, i in n.children {
            if i > 0 do strings.write_string(sb, ", ")
            pprint_node_inline(c, sb)
        }
        strings.write_string(sb, glyph("⟩", "|>"))
    case .Constraint:
        strings.write_string(sb, glyph("⌈", "[^"))
        for c in n.children do pprint_node_inline(c, sb)
        strings.write_string(sb, glyph("⌉", "^]"))
    case .Type_Prim:
        strings.write_string(sb, n.text)
    case .Type_Ref:
        strings.write_rune(sb, '&')
        for c in n.children do pprint_node_inline(c, sb)
    case .Type_Mut_Ref:
        strings.write_string(sb, "&mut ")
        for c in n.children do pprint_node_inline(c, sb)
    case .Type_Opt:
        for c in n.children do pprint_node_inline(c, sb)
        strings.write_rune(sb, '?')
    case .Type_Result:
        for c in n.children do pprint_node_inline(c, sb)
        strings.write_rune(sb, '!')
    case .Type_Linear:
        for c in n.children do pprint_node_inline(c, sb)
        strings.write_string(sb, "!lin")
    case .Type_Array:
        strings.write_rune(sb, '[')
        if len(n.children) > 0 do pprint_node_inline(n.children[0], sb)
        if len(n.children) > 1 {
            strings.write_string(sb, "; ")
            pprint_node_inline(n.children[1], sb)
        }
        strings.write_rune(sb, ']')
    case .Type_Tuple:
        if n.op == .Arrow_Right && len(n.children) >= 2 {
            pprint_node_inline(n.children[0], sb)
            strings.write_string(sb, " -> ")
            pprint_node_inline(n.children[1], sb)
        } else {
            strings.write_rune(sb, '(')
            for c, i in n.children {
                if i > 0 do strings.write_string(sb, ", ")
                pprint_node_inline(c, sb)
            }
            strings.write_rune(sb, ')')
        }
    case .Type_Union:
        if len(n.children) >= 2 {
            pprint_node_inline(n.children[0], sb)
            strings.write_string(sb, " | ")
            pprint_node_inline(n.children[1], sb)
        }
    case .Type_Map:
        strings.write_rune(sb, '{')
        if len(n.children) >= 2 {
            pprint_node_inline(n.children[0], sb)
            strings.write_string(sb, " : ")
            pprint_node_inline(n.children[1], sb)
        }
        strings.write_rune(sb, '}')
    case .Type_Record:
        strings.write_string(sb, glyph("⟨", "<|"))
        for c, i in n.children {
            if i > 0 do strings.write_string(sb, ", ")
            pprint_node_inline(c, sb)
        }
        strings.write_string(sb, glyph("⟩", "|>"))
    case .Field_Decl:
        if n.det != .Invalid do strings.write_string(sb, render_token(n.det))
        strings.write_string(sb, n.text)
        pprint_suffix(n, sb)
        if n.type_expr != nil {
            strings.write_string(sb, " : ")
            pprint_node_inline(n.type_expr, sb)
        }
        if n.constraint != nil {
            strings.write_rune(sb, ' ')
            pprint_node_inline(n.constraint, sb)
        }
    case .Param_Decl:
        strings.write_string(sb, n.text)
        pprint_suffix(n, sb)
        if n.type_expr != nil {
            strings.write_string(sb, " : ")
            pprint_node_inline(n.type_expr, sb)
        }
    case .Gate_Clause:
        strings.write_string(sb, n.text)
        strings.write_rune(sb, ' ')
        for c in n.children do pprint_node_inline(c, sb)
    case .Scope_Clause:
        strings.write_string(sb, n.text)
        for c in n.children do pprint_node_inline(c, sb)
    case .Lambda:
        strings.write_string(sb, "\\(")
        for i := 0; i < len(n.children) - 1; i += 1 {
            if i > 0 do strings.write_string(sb, ", ")
            pprint_node_inline(n.children[i], sb)
        }
        strings.write_string(sb, ") -> ")
        if len(n.children) > 0 do pprint_node_inline(n.children[len(n.children)-1], sb)
    case .Variant_Decl:
        strings.write_string(sb, n.text)
    case:
        // recursive fallback — render children in order
        for c in n.children do pprint_node_inline(c, sb)
    }
}

// Round-trip test helper: parse, print, reparse, compare AST shape
round_trip_ok :: proc(src: string, file: string) -> (ok: bool, reason: string) {
    doc1, _, perr1 := parse_source(src, file)
    if len(perr1) > 0 {
        return false, "original did not parse cleanly"
    }

    sb := strings.builder_make()
    pprint_doc(doc1, &sb)
    src2 := strings.to_string(sb)

    doc2, _, perr2 := parse_source(src2, file)
    if len(perr2) > 0 {
        return false, "reprinted source failed to reparse"
    }

    if !ast_shape_equal(doc1, doc2) {
        return false, "AST shape differs after round-trip"
    }
    return true, "ok"
}

// Shape equality: same kinds, same child counts, same ops/text for key roles.
// Permissive on numeric equality and order-insensitive collections.
ast_shape_equal :: proc(a, b: ^Node) -> bool {
    if a == nil && b == nil do return true
    if a == nil || b == nil do return false
    if a.kind != b.kind do return false
    if a.op != b.op do return false
    if len(a.children) != len(b.children) do return false
    // T23 (Session-5) : comment-position included in RT invariant
    if len(a.comments_before) != len(b.comments_before) do return false
    for i in 0 ..< len(a.comments_before) {
        if a.comments_before[i] != b.comments_before[i] do return false
    }
    for i in 0 ..< len(a.children) {
        if !ast_shape_equal(a.children[i], b.children[i]) do return false
    }
    if !ast_shape_equal(a.gate, b.gate) do return false
    if !ast_shape_equal(a.scope, b.scope) do return false
    if !ast_shape_equal(a.type_expr, b.type_expr) do return false
    if !ast_shape_equal(a.constraint, b.constraint) do return false
    return true
}
