package cslparser

// § CSLv3 PARSER — LEXER
// I> tokenizes CSLv3 source → Token stream w/ source positions
// W! handles unicode glyphs + ASCII aliases (same token kind)
// W! indentation → INDENT/DEDENT tokens (2 spaces per level)
// W! line/col tracking → error messages w/ snippet

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

Lex_Error :: struct {
    msg:     string,
    pos:     Source_Pos,
    snippet: string,
}

Lexer :: struct {
    src:            string,
    file:           string,
    pos:            int,      // byte offset
    line:           int,      // 1-based
    col:            int,      // 1-based
    tokens:         [dynamic]Token,
    errors:         [dynamic]Lex_Error,
    indent_stack:   [dynamic]int,
    at_line_start:  bool,
    paren_depth:    int,      // inside (), [], {} etc → suppress indent tracking
    pending_line_for_cont: int, // line we were on when last real token emitted
    emit_comments:  bool,
    // P2.2 (Session-12) : ADDITIVE prose-file tolerance.
    // When a file's header (first 1024 bytes) contains '# @prose-file'
    // OR '# corpus-mode: prose-file', the lexer silently skips runes it
    // doesn't recognize instead of emitting a lex-error. This lets
    // free-form handoff.csl files round-trip-parse without promoting
    // arbitrary Unicode to the 74-glyph master set (which would require
    // a v1.0 grammar change = MAJOR bump).
    // Narrow semantic : unknown runes are DROPPED, not preserved. The
    // round-trip invariant checks AST-shape + comment-position, both of
    // which remain stable under drop. Use only for prose documents that
    // are never read back programmatically.
    prose_tolerance: bool,
}

lexer_init :: proc(l: ^Lexer, src: string, file: string) {
    l.src = src
    l.file = file
    l.pos = 0
    l.line = 1
    l.col = 1
    l.tokens = make([dynamic]Token)
    l.errors = make([dynamic]Lex_Error)
    l.indent_stack = make([dynamic]int)
    append(&l.indent_stack, 0)
    l.at_line_start = true
    l.paren_depth = 0
    l.emit_comments = true   // T23 default : preserve comments for round-trip
    l.prose_tolerance = detect_prose_tolerance(src)
}

@(private="file")
detect_prose_tolerance :: proc(src: string) -> bool {
    // P2.2 (Session-12) : scan the whole file for an opt-in directive.
    // Two spellings accepted for compatibility with the §§10 corpus-mode
    // convention already used by m₁ fixtures.
    // Full-file scan (not head-only) so round-trip stays stable even when
    // pprint relocates the directive into a section body.
    if strings.contains(src, "# @prose-file") do return true
    if strings.contains(src, "# corpus-mode: prose-file") do return true
    return false
}

lexer_destroy :: proc(l: ^Lexer) {
    delete(l.tokens)
    delete(l.errors)
    delete(l.indent_stack)
}

@(private="file")
cur_pos :: proc(l: ^Lexer) -> Source_Pos {
    return Source_Pos{file = l.file, line = l.line, col = l.col, offset = l.pos}
}

@(private="file")
peek_byte :: proc(l: ^Lexer, off: int = 0) -> u8 {
    p := l.pos + off
    if p >= len(l.src) do return 0
    return l.src[p]
}

@(private="file")
decode_rune_here :: proc(l: ^Lexer) -> (rune, int) {
    if l.pos >= len(l.src) do return 0, 0
    r, w := utf8.decode_rune_in_string(l.src[l.pos:])
    return r, w
}

@(private="file")
advance_byte :: proc(l: ^Lexer, n: int = 1) {
    for i in 0 ..< n {
        if l.pos >= len(l.src) do return
        c := l.src[l.pos]
        l.pos += 1
        if c == '\n' {
            l.line += 1
            l.col = 1
        } else {
            l.col += 1
        }
    }
}

@(private="file")
advance_rune :: proc(l: ^Lexer) {
    if l.pos >= len(l.src) do return
    _, w := utf8.decode_rune_in_string(l.src[l.pos:])
    c := l.src[l.pos]
    l.pos += w
    if c == '\n' {
        l.line += 1
        l.col = 1
    } else {
        l.col += 1
    }
}

@(private="file")
match_str :: proc(l: ^Lexer, s: string) -> bool {
    if l.pos + len(s) > len(l.src) do return false
    return l.src[l.pos:l.pos + len(s)] == s
}

@(private="file")
emit :: proc(l: ^Lexer, kind: Token_Kind, text: string, pos: Source_Pos) {
    append(&l.tokens, Token{kind = kind, text = text, pos = pos})
}

@(private="file")
add_error :: proc(l: ^Lexer, msg: string, pos: Source_Pos) {
    // P2.2 : silence lex errors in prose-file mode.
    // All lex-error paths (unknown-char, inconsistent-indent, etc.) flow
    // through here, so a single guard gives uniform tolerance semantics.
    if l.prose_tolerance do return
    append(&l.errors, Lex_Error{msg = msg, pos = pos, snippet = line_snippet(l.src, pos.line)})
}

line_snippet :: proc(src: string, line: int) -> string {
    cur := 1
    start := 0
    end := len(src)
    for i in 0 ..< len(src) {
        if cur == line && i >= start {
            // find end of this line
            end = i
            for end < len(src) && src[end] != '\n' do end += 1
            return src[start:end]
        }
        if src[i] == '\n' {
            cur += 1
            start = i + 1
        }
    }
    if cur == line && start < len(src) {
        end = start
        for end < len(src) && src[end] != '\n' do end += 1
        return src[start:end]
    }
    return ""
}

// keyword/identifier lookup — maps well-known words to their token kinds
@(private="file")
classify_ident :: proc(text: string) -> Token_Kind {
    switch text {
    case "fn":       return .Kw_Fn
    case "def":      return .Kw_Def
    case "enum":     return .Kw_Enum
    case "let":      return .Kw_Let
    case "pub":      return .Kw_Pub
    case "use":      return .Kw_Use
    case "alias":    return .Kw_Alias
    case "match":    return .Kw_Match
    case "if":       return .Kw_If
    case "when":     return .Kw_When
    case "unless":   return .Kw_Unless
    case "while":    return .Kw_While
    case "per":      return .Kw_Per
    case "true":     return .Kw_True
    case "false":    return .Kw_False
    case "nil":      return .Kw_Nil
    case "pre":      return .Kw_Pre
    case "post":     return .Kw_Post
    case "all":      return .ForAll
    case "any":      return .Exists
    case "in":       return .In
    case "inf":      return .Infinity
    case "xor":      return .Xor
    case "QED":      return .QED
    case "TODO":     return .Modal_Todo
    case "FIXME":    return .Modal_Fixme
    case "loop":     return .Iterate
    case "grad":     return .Nabla
    case "u8":       return .Prim_U8
    case "u16":      return .Prim_U16
    case "u32":      return .Prim_U32
    case "u64":      return .Prim_U64
    case "i8":       return .Prim_I8
    case "i16":      return .Prim_I16
    case "i32":      return .Prim_I32
    case "i64":      return .Prim_I64
    case "f32":      return .Prim_F32
    case "f64":      return .Prim_F64
    case "bool":     return .Prim_Bool
    case "str":      return .Prim_Str
    case "vec2":     return .Prim_Vec2
    case "vec3":     return .Prim_Vec3
    case "vec4":     return .Prim_Vec4
    case "mat4":     return .Prim_Mat4
    case "quat":     return .Prim_Quat
    case "rgba":     return .Prim_Rgba
    }
    return .Ident
}

@(private="file")
is_ident_start :: proc(r: rune) -> bool {
    return (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '_'
}

@(private="file")
is_ident_cont :: proc(r: rune) -> bool {
    return is_ident_start(r) || (r >= '0' && r <= '9')
}

@(private="file")
is_digit :: proc(r: rune) -> bool {
    return r >= '0' && r <= '9'
}

@(private="file")
is_hex :: proc(r: rune) -> bool {
    return is_digit(r) || (r >= 'a' && r <= 'f') || (r >= 'A' && r <= 'F')
}

// handle indentation at line start: emit INDENT / DEDENT tokens as needed
@(private="file")
handle_indent :: proc(l: ^Lexer) {
    start_pos := l.pos
    spaces := 0
    for l.pos < len(l.src) {
        c := l.src[l.pos]
        if c == ' ' {
            spaces += 1
            advance_byte(l)
        } else if c == '\t' {
            spaces += 4
            advance_byte(l)
        } else {
            break
        }
    }

    // blank line or comment-only line — no indent emission
    if l.pos >= len(l.src) do return
    c := l.src[l.pos]
    if c == '\n' || c == '\r' do return
    if c == '#' do return  // comment-only lines don't change indent

    _ = start_pos

    cur_top := l.indent_stack[len(l.indent_stack)-1]
    if spaces > cur_top {
        append(&l.indent_stack, spaces)
        emit(l, .Indent, "", cur_pos(l))
    } else {
        for spaces < l.indent_stack[len(l.indent_stack)-1] {
            pop(&l.indent_stack)
            emit(l, .Dedent, "", cur_pos(l))
        }
        if spaces != l.indent_stack[len(l.indent_stack)-1] {
            add_error(l, fmt.tprintf("inconsistent indentation: %d spaces does not match any outer indent level", spaces), cur_pos(l))
        }
    }
    l.at_line_start = false
}

// read an identifier — may end with a type suffix 'd 'f 's ... handled separately
// also merges karmadhāraya compounds: `static-mesh`, `flora-species` → single IDENT
@(private="file")
lex_ident :: proc(l: ^Lexer) {
    start := l.pos
    start_pos := cur_pos(l)
    for l.pos < len(l.src) {
        r, w := decode_rune_here(l)
        if is_ident_cont(r) {
            _ = w
            advance_rune(l)
            continue
        }
        // karmadhāraya merge: IDENT `-` IDENT w/o whitespace → single ident
        if r == '-' && l.pos + 1 < len(l.src) {
            nxt := l.src[l.pos + 1]
            if is_ident_start(rune(nxt)) {
                advance_byte(l)
                continue
            }
        }
        break
    }
    text := l.src[start:l.pos]
    kind := classify_ident(text)
    // compound idents (containing '-') are never keywords — force Ident
    if kind != .Ident {
        for c in text {
            if c == '-' {
                kind = .Ident
                break
            }
        }
    }
    emit(l, kind, text, start_pos)
}

// read a number — int, float, hex (0x), binary (0b)
@(private="file")
lex_number :: proc(l: ^Lexer) {
    start := l.pos
    start_pos := cur_pos(l)
    is_float := false
    // hex / binary prefix
    if peek_byte(l) == '0' && (peek_byte(l, 1) == 'x' || peek_byte(l, 1) == 'X') {
        advance_byte(l, 2)
        for l.pos < len(l.src) {
            c := l.src[l.pos]
            if is_hex(rune(c)) || c == '_' do advance_byte(l)
            else do break
        }
    } else if peek_byte(l) == '0' && (peek_byte(l, 1) == 'b' || peek_byte(l, 1) == 'B') {
        advance_byte(l, 2)
        for l.pos < len(l.src) {
            c := l.src[l.pos]
            if c == '0' || c == '1' || c == '_' do advance_byte(l)
            else do break
        }
    } else {
        for l.pos < len(l.src) {
            c := l.src[l.pos]
            if is_digit(rune(c)) || c == '_' do advance_byte(l)
            else do break
        }
        // fractional part — but NOT if it's `..` range
        if peek_byte(l) == '.' && peek_byte(l, 1) != '.' && is_digit(rune(peek_byte(l, 1))) {
            is_float = true
            advance_byte(l) // consume .
            for l.pos < len(l.src) {
                c := l.src[l.pos]
                if is_digit(rune(c)) || c == '_' do advance_byte(l)
                else do break
            }
        }
        // exponent
        if l.pos < len(l.src) && (l.src[l.pos] == 'e' || l.src[l.pos] == 'E') {
            is_float = true
            advance_byte(l)
            if l.pos < len(l.src) && (l.src[l.pos] == '+' || l.src[l.pos] == '-') {
                advance_byte(l)
            }
            for l.pos < len(l.src) {
                c := l.src[l.pos]
                if is_digit(rune(c)) do advance_byte(l)
                else do break
            }
        }
    }
    text := l.src[start:l.pos]
    tok := Token{kind = .Number, text = text, pos = start_pos, is_float = is_float}
    cleaned, _ := strings.replace_all(text, "_", "", context.temp_allocator)
    if is_float {
        f, ok := strconv.parse_f64(cleaned)
        if ok do tok.float_val = f
    } else {
        if strings.has_prefix(cleaned, "0x") || strings.has_prefix(cleaned, "0X") {
            n, ok := strconv.parse_i64(cleaned[2:], 16)
            if ok do tok.int_val = n
        } else if strings.has_prefix(cleaned, "0b") || strings.has_prefix(cleaned, "0B") {
            n, ok := strconv.parse_i64(cleaned[2:], 2)
            if ok do tok.int_val = n
        } else {
            n, ok := strconv.parse_i64(cleaned)
            if ok do tok.int_val = n
        }
    }
    append(&l.tokens, tok)
}

// read a string literal — "..." or `...` (raw)
@(private="file")
lex_string :: proc(l: ^Lexer, delim: u8) {
    start_pos := cur_pos(l)
    advance_byte(l) // consume opening delim
    start := l.pos
    for l.pos < len(l.src) {
        c := l.src[l.pos]
        if c == delim {
            text := l.src[start:l.pos]
            advance_byte(l) // consume closing delim
            emit(l, .String, text, start_pos)
            return
        }
        if delim == '"' && c == '\\' {
            advance_byte(l)
            if l.pos < len(l.src) do advance_byte(l)
            continue
        }
        if c == '\n' && delim == '"' {
            add_error(l, "unterminated string literal", start_pos)
            emit(l, .Invalid, l.src[start:l.pos], start_pos)
            return
        }
        advance_byte(l)
    }
    add_error(l, "unterminated string literal at EOF", start_pos)
    emit(l, .Invalid, l.src[start:l.pos], start_pos)
}

// try to read a type suffix `'X` where X ∈ {d,f,s,t,e,m,p,g,r}
@(private="file")
try_lex_suffix :: proc(l: ^Lexer) -> bool {
    if peek_byte(l) != '\'' do return false
    nxt := peek_byte(l, 1)
    kind: Token_Kind
    switch nxt {
    case 'd': kind = .Suffix_Data
    case 'f': kind = .Suffix_Func
    case 's': kind = .Suffix_System
    case 't': kind = .Suffix_Type
    case 'e': kind = .Suffix_Entity
    case 'm': kind = .Suffix_Material
    case 'p': kind = .Suffix_Prop
    case 'g': kind = .Suffix_Gate
    case 'r': kind = .Suffix_Rule
    case:     return false
    }
    // ensure it's not the start of something else (like 'd followed by alnum that would make it an identifier)
    after := peek_byte(l, 2)
    if is_ident_cont(rune(after)) do return false
    start_pos := cur_pos(l)
    advance_byte(l, 2)
    emit(l, kind, l.src[start_pos.offset:l.pos], start_pos)
    return true
}

// try to match a bracket-alias evidence token like [x] [~] [ ] [!] [?] [^] [v] [!!]
@(private="file")
try_lex_bracket_alias :: proc(l: ^Lexer) -> bool {
    if peek_byte(l) != '[' do return false
    // try 4-char form first: [!!]
    if peek_byte(l, 1) == '!' && peek_byte(l, 2) == '!' && peek_byte(l, 3) == ']' {
        p := cur_pos(l)
        advance_byte(l, 4)
        emit(l, .Ev_Proven, "[!!]", p)
        return true
    }
    // 3-char forms: [X]
    if peek_byte(l, 2) == ']' {
        mid := peek_byte(l, 1)
        kind: Token_Kind
        text: string
        switch mid {
        case 'x': kind = .Ev_Confirmed;    text = "[x]"
        case '~': kind = .Ev_Partial;      text = "[~]"
        case ' ': kind = .Ev_Pending;      text = "[ ]"
        case '!': kind = .Ev_Failed;       text = "[!]"
        case '?': kind = .Ev_Unknown;      text = "[?]"
        case '^': kind = .Ev_Hypothetical; text = "[^]"
        case 'v': kind = .Ev_Deprecated;   text = "[v]"
        case:     return false
        }
        p := cur_pos(l)
        advance_byte(l, 3)
        emit(l, kind, text, p)
        return true
    }
    return false
}

// Main token loop — dispatches on current char
tokenize :: proc(l: ^Lexer) {
    for l.pos < len(l.src) {
        if l.at_line_start && l.paren_depth == 0 {
            handle_indent(l)
            if l.pos >= len(l.src) do break
        }
        // skip horizontal whitespace (not at line start)
        c := l.src[l.pos]
        if c == ' ' || c == '\t' {
            advance_byte(l)
            continue
        }
        // newline
        if c == '\n' {
            if l.paren_depth == 0 {
                emit(l, .Newline, "\\n", cur_pos(l))
            }
            advance_byte(l)
            l.at_line_start = true
            continue
        }
        if c == '\r' {
            advance_byte(l)
            continue
        }
        // comment
        if c == '#' {
            // collect to EOL
            start_pos := cur_pos(l)
            start := l.pos
            for l.pos < len(l.src) && l.src[l.pos] != '\n' {
                advance_byte(l)
            }
            if l.emit_comments {
                emit(l, .Comment, l.src[start:l.pos], start_pos)
            }
            continue
        }
        start_pos := cur_pos(l)
        _ = start_pos

        // === multi-char ASCII aliases & operators ===

        // ASCII glyph aliases — longest match first
        if try_lex_bracket_alias(l) do continue

        // string literals
        if c == '"' {
            lex_string(l, '"')
            continue
        }
        if c == '`' {
            lex_string(l, '`')
            continue
        }
        // suffix (quote + letter)
        if c == '\'' {
            if try_lex_suffix(l) do continue
            p := cur_pos(l)
            advance_byte(l)
            emit(l, .Invalid, "'", p)
            continue
        }

        // 3-char ASCII alias patterns
        if l.pos + 3 <= len(l.src) {
            s3 := l.src[l.pos:l.pos+3]
            p := cur_pos(l)
            k: Token_Kind = .Invalid
            switch s3 {
            case "<->": k = .Arrow_Bidi
            case ".:.": k = .Therefore
            case ":..": k = .Because
            case "===": k = .Identical
            }
            if k != .Invalid {
                advance_byte(l, 3)
                emit(l, k, s3, p)
                continue
            }
        }

        // 2-char ASCII alias patterns (longest-match)
        if l.pos + 2 <= len(l.src) {
            s2 := l.src[l.pos:l.pos+2]
            p := cur_pos(l)
            k: Token_Kind = .Invalid
            switch s2 {
            case "->": k = .Arrow_Right
            case "S:": k = .Section   // T23 : ASCII alias for §
            case "<-": k = .Arrow_Left
            case "=>": k = .Implies
            case "|-": k = .Entails
            case "::": k = .DoubleColon
            case "..": k = .Range
            case "!=": k = .NotEq
            case "<=": k = .Lte
            case ">=": k = .Gte
            case "==": k = .EqEq
            case "|>": k = .PipeFwd
            case "<|": k = .PipeBack
            case ">>": k = .Dispatch
            case "<<": k = .Receive
            case "~>": k = .Causes
            case "|+": k = .Union
            case "&+": k = .Intersect
            case "<:": k = .Subset
            case ":>": k = .Superset
            case "!?": k = .Suspect
            case "?!": k = .Surprising
            case "||": k = .Or
            case "&&": k = .And
            case "~=": k = .Approx
            case "+=": k = .Plus_Eq
            case "-=": k = .Minus_Eq
            case "*=": k = .Star_Eq
            case "/=": k = .Slash_Eq
            case "d/": k = .Partial
            case "x*": k = .Tensor
            case "*!": k = .KeyInsight
            case "//": k = .NoteSelf
            case "^^": k = .Lift
            case "vv": k = .Dive
            }
            if k != .Invalid {
                // special-case: `!in` → NotIn (handle here before Bang)
                advance_byte(l, 2)
                emit(l, k, s2, p)
                continue
            }
        }

        // modal markers (W!, R!, M?, N!, I>, Q?, P>, D>)
        if l.pos + 2 <= len(l.src) {
            s2 := l.src[l.pos:l.pos+2]
            // these conflict with ident starts (W, R, M, N, I, Q, P, D) — only if followed by non-ident
            k: Token_Kind = .Invalid
            switch s2 {
            case "W!": k = .Modal_Must
            case "R!": k = .Modal_Should
            case "M?": k = .Modal_May
            case "N!": k = .Modal_MustNot
            case "I>": k = .Modal_Insight
            case "Q?": k = .Modal_Question
            case "P>": k = .Modal_Push
            case "D>": k = .Modal_Decision
            }
            if k != .Invalid {
                // must be followed by whitespace/EOL/non-ident-cont
                after := peek_byte(l, 2)
                if !is_ident_cont(rune(after)) {
                    p := cur_pos(l)
                    advance_byte(l, 2)
                    emit(l, k, s2, p)
                    continue
                }
            }
        }

        // !in — NotIn
        if c == '!' && l.pos + 3 <= len(l.src) {
            if l.src[l.pos:l.pos+3] == "!in" {
                after := peek_byte(l, 3)
                if !is_ident_cont(rune(after)) {
                    p := cur_pos(l)
                    advance_byte(l, 3)
                    emit(l, .NotIn, "!in", p)
                    continue
                }
            }
        }

        // ASCII byte-level single char
        if c < 0x80 {
            p := cur_pos(l)
            switch c {
            case '.':
                advance_byte(l)
                emit(l, .Dot, ".", p)
                continue
            case '+':
                advance_byte(l)
                emit(l, .Plus, "+", p)
                continue
            case '-':
                advance_byte(l)
                emit(l, .Minus, "-", p)
                continue
            case '@':
                advance_byte(l)
                emit(l, .At, "@", p)
                continue
            case ':':
                advance_byte(l)
                emit(l, .Colon, ":", p)
                continue
            case '=':
                advance_byte(l)
                emit(l, .Eq, "=", p)
                continue
            case '|':
                advance_byte(l)
                emit(l, .Pipe, "|", p)
                continue
            case '&':
                advance_byte(l)
                emit(l, .Amp, "&", p)
                continue
            case '!':
                advance_byte(l)
                emit(l, .Bang, "!", p)
                continue
            case '?':
                advance_byte(l)
                emit(l, .Question, "?", p)
                continue
            case '*':
                advance_byte(l)
                emit(l, .Star, "*", p)
                continue
            case '^':
                advance_byte(l)
                emit(l, .Caret, "^", p)
                continue
            case '_':
                // could be underscore placeholder OR ident start
                // if followed by ident-cont → ident; else standalone
                if is_ident_cont(rune(peek_byte(l, 1))) {
                    lex_ident(l)
                } else {
                    advance_byte(l)
                    emit(l, .Underscore, "_", p)
                }
                continue
            case '/':
                advance_byte(l)
                emit(l, .Slash, "/", p)
                continue
            case '\\':
                advance_byte(l)
                emit(l, .Backslash, "\\", p)
                continue
            case '%':
                advance_byte(l)
                emit(l, .Percent, "%", p)
                continue
            case '$':
                // $N positional reference
                advance_byte(l)
                if l.pos < len(l.src) && is_digit(rune(l.src[l.pos])) {
                    dstart := l.pos
                    for l.pos < len(l.src) && is_digit(rune(l.src[l.pos])) do advance_byte(l)
                    emit(l, .PosRef, l.src[dstart:l.pos], p)
                } else if l.pos < len(l.src) && is_ident_start(rune(l.src[l.pos])) {
                    // $name variable
                    dstart := l.pos
                    for l.pos < len(l.src) && is_ident_cont(rune(l.src[l.pos])) do advance_byte(l)
                    emit(l, .Dollar, l.src[p.offset:l.pos], p)
                } else {
                    emit(l, .Dollar, "$", p)
                }
                continue
            case ',':
                advance_byte(l)
                emit(l, .Comma, ",", p)
                continue
            case ';':
                advance_byte(l)
                emit(l, .Semi, ";", p)
                continue
            case '~':
                advance_byte(l)
                emit(l, .Tilde, "~", p)
                continue
            case '<':
                advance_byte(l)
                emit(l, .Lt, "<", p)
                continue
            case '>':
                advance_byte(l)
                emit(l, .Gt, ">", p)
                continue
            case '(':
                advance_byte(l)
                l.paren_depth += 1
                emit(l, .LParen, "(", p)
                continue
            case ')':
                advance_byte(l)
                if l.paren_depth > 0 do l.paren_depth -= 1
                emit(l, .RParen, ")", p)
                continue
            case '[':
                advance_byte(l)
                l.paren_depth += 1
                emit(l, .LBracket, "[", p)
                continue
            case ']':
                advance_byte(l)
                if l.paren_depth > 0 do l.paren_depth -= 1
                emit(l, .RBracket, "]", p)
                continue
            case '{':
                advance_byte(l)
                l.paren_depth += 1
                emit(l, .LBrace, "{", p)
                continue
            case '}':
                advance_byte(l)
                if l.paren_depth > 0 do l.paren_depth -= 1
                emit(l, .RBrace, "}", p)
                continue
            }
            // identifier
            if is_ident_start(rune(c)) {
                lex_ident(l)
                continue
            }
            // number
            if is_digit(rune(c)) {
                lex_number(l)
                continue
            }
            // unrecognized ASCII
            advance_byte(l)
            emit(l, .Invalid, l.src[p.offset:l.pos], p)
            continue
        }

        // === unicode rune dispatch ===
        r, w := decode_rune_here(l)
        p := cur_pos(l)
        kind: Token_Kind = .Invalid
        text := l.src[l.pos:l.pos+w]
        switch r {
        // structural
        case '§': kind = .Section
        // flow
        case '→': kind = .Arrow_Right
        case '←': kind = .Arrow_Left
        case '↔': kind = .Arrow_Bidi
        case '⇒': kind = .Implies
        case '⊢': kind = .Entails
        case '∴': kind = .Therefore
        case '∵': kind = .Because
        case '∎': kind = .QED
        // set/logic
        case '∀': kind = .ForAll
        case '∃': kind = .Exists
        case '∈': kind = .In
        case '∉': kind = .NotIn
        case '∪': kind = .Union
        case '∩': kind = .Intersect
        case '⊂': kind = .Subset
        case '⊃': kind = .Superset
        case '¬': kind = .Not
        case '∧': kind = .And
        case '∨': kind = .Or
        case '⊕': kind = .Xor
        case '⊗': kind = .Tensor
        case '≡': kind = .Identical
        case '≈': kind = .Approx
        case '≥': kind = .Gte
        case '≤': kind = .Lte
        case '≠': kind = .NotEq
        case '∞': kind = .Infinity
        case '∅': kind = .Empty
        // enclosures
        case '⟨': kind = .LAngle;       l.paren_depth += 1
        case '⟩': kind = .RAngle;       if l.paren_depth > 0 do l.paren_depth -= 1
        case '⟦': kind = .LFormula;     l.paren_depth += 1
        case '⟧': kind = .RFormula;     if l.paren_depth > 0 do l.paren_depth -= 1
        case '«': kind = .LQuote_Ext;   l.paren_depth += 1
        case '»': kind = .RQuote_Ext;   if l.paren_depth > 0 do l.paren_depth -= 1
        case '⌈': kind = .LConstraint;  l.paren_depth += 1
        case '⌉': kind = .RConstraint;  if l.paren_depth > 0 do l.paren_depth -= 1
        case '⌊': kind = .LPre;         l.paren_depth += 1
        case '⌋': kind = .RPre;         if l.paren_depth > 0 do l.paren_depth -= 1
        case '⟪': kind = .LTemporal;    l.paren_depth += 1
        case '⟫': kind = .RTemporal;    if l.paren_depth > 0 do l.paren_depth -= 1
        // evidence
        case '✓': kind = .Ev_Confirmed
        case '◐': kind = .Ev_Partial
        case '○': kind = .Ev_Pending
        case '✗': kind = .Ev_Failed
        case '⊘': kind = .Ev_Unknown
        case '△': kind = .Ev_Hypothetical
        case '▽': kind = .Ev_Deprecated
        case '‼': kind = .Ev_Proven
        // determinatives
        case '∫': kind = .Det_Field
        case '⊞': kind = .Det_Spatial
        // temporal / math
        case 'Δ': kind = .Delta
        case '∂': kind = .Partial
        case '∇': kind = .Nabla
        case 'λ': kind = .Lambda
        // reasoning glyphs
        case '⟲': kind = .Iterate
        case '⤓': kind = .Dive
        case '⤒': kind = .Lift
        case '⟐': kind = .Pivot
        case '⚠': kind = .Warning
        case '★': kind = .KeyInsight
        case '✎': kind = .NoteSelf
        // physics / material
        case 'ρ': kind = .Phys_Rho
        case 'μ': kind = .Phys_Mu
        case 'σ': kind = .Phys_Sigma
        case 'κ': kind = .Phys_Kappa
        case 'ε': kind = .Phys_Epsilon
        case 'τ': kind = .Phys_Tau
        // bullet / middot — treat as conjunction (∧) for arithmetic/text use
        case '·': kind = .Star   // multiplication operator in math contexts
        // centered dot alias for tatpurusha extension — rare
        }
        if kind != .Invalid {
            advance_rune(l)
            emit(l, kind, text, p)
            continue
        }

        // Unknown rune — either flag (default) or silently-skip (prose-file).
        // P2.2 (Session-12) : when the file opts into prose-tolerance, drop
        // the rune without emitting either a lex-error or an Invalid token.
        // The AST-shape round-trip still holds because both directions drop
        // the same runes.
        if l.prose_tolerance {
            advance_rune(l)
        } else {
            add_error(l, fmt.tprintf("unrecognized character '%r' (U+%04X)", r, r), p)
            advance_rune(l)
            emit(l, .Invalid, text, p)
        }
    }

    // drain remaining DEDENTs
    for len(l.indent_stack) > 1 {
        pop(&l.indent_stack)
        emit(l, .Dedent, "", cur_pos(l))
    }
    emit(l, .EOF, "", cur_pos(l))
}

// Convenience: lex a source string into a token slice
lex_source :: proc(src: string, file: string) -> (tokens: []Token, errors: []Lex_Error) {
    l: Lexer
    lexer_init(&l, src, file)
    tokenize(&l)
    tokens = l.tokens[:]
    errors = l.errors[:]
    return
}
