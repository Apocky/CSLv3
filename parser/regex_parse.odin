package cslparser

// § A8 Session-15 : regex pattern parser (pattern → AST).
//
// I> hand-written recursive descent over the regex subset defined in
//    the Session-15 handoff §§ FEATURE MATRIX.
// I> Unicode-aware : scans runes not bytes inside [] character classes
//    and for \p{X} property escapes.
//
// Grammar (subset) :
//   re         := alt
//   alt        := concat ('|' concat)*
//   concat     := repeat*
//   repeat     := atom ('*'|'+'|'?'|'{'n[',']m'}') ('?'  lazy)?
//   atom       := '(' ['?:' | '?<' name '>' ] re ')'
//              |  '[' class-body ']'
//              |  '\' escape
//              |  '.' | '^' | '$'
//              |  literal-rune
//   class-body := '^'? class-atom (class-atom)*
//   class-atom := rune ('-' rune)? | '\' escape | '\p{Name}'

import "core:fmt"
import "core:strings"

// ------------------------- AST types -------------------------

Re_Kind :: enum u8 {
    Lit,            // a single rune
    AnyChar,        // .
    CharClass,      // [...]
    Anchor_BOS,     // ^
    Anchor_EOS,     // $
    Anchor_BOW,     // \b
    Anchor_NBOW,    // \B
    Concat,         // children in sequence
    Alt,            // children alternatives
    Repeat,         // child repeated
    Group,          // capturing (?<name>..) or plain (..)
    NonCaptGroup,   // (?:..)
    Backref,        // \1, \k<name>
}

Re_Node :: struct {
    kind:      Re_Kind,
    rune_val:  rune,                 // for Lit
    class:     ^Char_Class,          // for CharClass
    lo, hi:    int,                  // for Repeat (hi = -1 → unbounded)
    lazy:      bool,                 // for Repeat
    group_idx: int,                  // for Group (1-based ; 0 = whole)
    group_name: string,
    backref:   int,                  // for Backref (1-based index)
    children: [dynamic]^Re_Node,
}

// Character-class descriptor :
//   - explicit rune-ranges
//   - a set of "kind flags" for built-ins (\d \s \w) + negations
//   - negated : whole class
Char_Class_Flag :: enum u8 {
    Ascii_Digit,     // \d
    Not_Ascii_Digit, // \D
    Ascii_Space,     // \s
    Not_Ascii_Space, // \S
    Ascii_Word,      // \w
    Not_Ascii_Word,  // \W
    Unicode_Letter,  // \p{L}
    Unicode_Number,  // \p{N}
    Unicode_Punct,   // \p{P}
    Unicode_Symbol,  // \p{S}
    Any_Dot,         // .  (any except \n)
}

Char_Class :: struct {
    negated: bool,
    ranges:  [dynamic]Rune_Range,
    flags:   bit_set[Char_Class_Flag],
}

// ------------------------- error type -------------------------

Regex_Err :: struct {
    ok:  bool,
    msg: string,
    pos: int,
}

// ------------------------- parser state -------------------------

@(private="file")
Re_Parser :: struct {
    src: string,
    idx: int,
    group_counter: int,
    group_names: [dynamic]string,  // index 0 unused ; aligns with group_idx
}

@(private="file")
rpeek :: #force_inline proc(p: ^Re_Parser) -> u8 {
    return 0 if p.idx >= len(p.src) else p.src[p.idx]
}

@(private="file")
radv :: #force_inline proc(p: ^Re_Parser) -> u8 {
    c := rpeek(p); p.idx += 1; return c
}

@(private="file")
rerr :: proc(p: ^Re_Parser, msg: string) -> Regex_Err {
    return Regex_Err{ ok = false, msg = msg, pos = p.idx }
}

// ------------------------- public entrypoint -------------------------

regex_parse_pattern :: proc(pattern: string, allocator := context.allocator) -> (^Re_Node, Regex_Err) {
    context.allocator = allocator
    p := Re_Parser{ src = pattern }
    // Reserve group 0 (= whole match).
    append(&p.group_names, strings.clone(""))
    p.group_counter = 0
    node, err := parse_alt(&p)
    if !err.ok do return nil, err
    if p.idx != len(pattern) {
        return nil, rerr(&p, "unexpected trailing characters")
    }
    return node, Regex_Err{ ok = true }
}

// ------------------------- alt / concat -------------------------

@(private="file")
parse_alt :: proc(p: ^Re_Parser) -> (^Re_Node, Regex_Err) {
    first, err := parse_concat(p)
    if !err.ok do return nil, err
    if rpeek(p) != '|' do return first, Regex_Err{ ok = true }

    // We have one or more alternatives.
    alt := new(Re_Node)
    alt.kind = .Alt
    append(&alt.children, first)
    for rpeek(p) == '|' {
        radv(p)
        branch, e := parse_concat(p)
        if !e.ok do return nil, e
        append(&alt.children, branch)
    }
    return alt, Regex_Err{ ok = true }
}

@(private="file")
parse_concat :: proc(p: ^Re_Parser) -> (^Re_Node, Regex_Err) {
    parts := make([dynamic]^Re_Node, 0, 8)
    for {
        c := rpeek(p)
        if c == 0 || c == '|' || c == ')' do break
        node, err := parse_repeat(p)
        if !err.ok do return nil, err
        if node != nil do append(&parts, node)
    }
    if len(parts) == 0 {
        // Empty pattern (e.g. `a|` second branch) → literal epsilon : emit
        // an empty Concat. The compiler handles it as MATCH-through.
        n := new(Re_Node); n.kind = .Concat
        return n, Regex_Err{ ok = true }
    }
    if len(parts) == 1 do return parts[0], Regex_Err{ ok = true }
    n := new(Re_Node); n.kind = .Concat
    for c in parts do append(&n.children, c)
    return n, Regex_Err{ ok = true }
}

@(private="file")
parse_repeat :: proc(p: ^Re_Parser) -> (^Re_Node, Regex_Err) {
    atom, err := parse_atom(p)
    if !err.ok do return nil, err
    if atom == nil do return nil, Regex_Err{ ok = true }

    c := rpeek(p)
    if c != '*' && c != '+' && c != '?' && c != '{' do return atom, Regex_Err{ ok = true }

    r := new(Re_Node)
    r.kind = .Repeat
    switch c {
    case '*': radv(p); r.lo = 0; r.hi = -1
    case '+': radv(p); r.lo = 1; r.hi = -1
    case '?': radv(p); r.lo = 0; r.hi = 1
    case '{':
        radv(p)
        n1 := parse_int(p)
        if n1 < 0 do return nil, rerr(p, "expected number after '{'")
        r.lo = n1
        if rpeek(p) == '}' {
            r.hi = n1
            radv(p)
        } else if rpeek(p) == ',' {
            radv(p)
            if rpeek(p) == '}' {
                r.hi = -1   // {n,}
                radv(p)
            } else {
                n2 := parse_int(p)
                if n2 < 0 do return nil, rerr(p, "expected number after ','")
                if n2 < n1 do return nil, rerr(p, "upper bound < lower bound")
                r.hi = n2
                if rpeek(p) != '}' do return nil, rerr(p, "expected '}'")
                radv(p)
            }
        } else {
            return nil, rerr(p, "malformed {n,m}")
        }
    }
    // lazy suffix
    if rpeek(p) == '?' { radv(p); r.lazy = true }
    append(&r.children, atom)
    return r, Regex_Err{ ok = true }
}

@(private="file")
parse_int :: proc(p: ^Re_Parser) -> int {
    start := p.idx
    v := 0
    for {
        c := rpeek(p)
        if c < '0' || c > '9' do break
        v = v * 10 + int(c - '0')
        radv(p)
    }
    return -1 if p.idx == start else v
}

@(private="file")
parse_atom :: proc(p: ^Re_Parser) -> (^Re_Node, Regex_Err) {
    c := rpeek(p)
    if c == 0 do return nil, Regex_Err{ ok = true }

    switch c {
    case '(':
        return parse_group(p)
    case '[':
        return parse_class(p)
    case '.':
        radv(p)
        n := new(Re_Node); n.kind = .AnyChar
        return n, Regex_Err{ ok = true }
    case '^':
        radv(p)
        n := new(Re_Node); n.kind = .Anchor_BOS
        return n, Regex_Err{ ok = true }
    case '$':
        radv(p)
        n := new(Re_Node); n.kind = .Anchor_EOS
        return n, Regex_Err{ ok = true }
    case '\\':
        return parse_escape(p)
    case '|', ')':
        return nil, Regex_Err{ ok = true }
    }

    // Literal : decode one rune.
    r, sz := utf8_decode(p.src, p.idx)
    if sz == 0 do return nil, rerr(p, "bad rune")
    p.idx += sz
    n := new(Re_Node)
    n.kind = .Lit
    n.rune_val = r
    return n, Regex_Err{ ok = true }
}

@(private="file")
parse_group :: proc(p: ^Re_Parser) -> (^Re_Node, Regex_Err) {
    radv(p)   // consume '('
    non_capt := false
    name: string
    if rpeek(p) == '?' {
        radv(p)
        nc := rpeek(p)
        if nc == ':' {
            radv(p)
            non_capt = true
        } else if nc == '<' || nc == 'P' {
            // (?<name>..) or (?P<name>..)
            if nc == 'P' { radv(p); if rpeek(p) != '<' do return nil, rerr(p, "expected '<'") }
            radv(p)  // consume '<'
            sb := strings.builder_make()
            for {
                nk := rpeek(p)
                if nk == '>' { radv(p); break }
                if nk == 0 do return nil, rerr(p, "unterminated group name")
                strings.write_byte(&sb, nk)
                radv(p)
            }
            name = strings.to_string(sb)
        } else {
            return nil, rerr(p, "unsupported (? ... ) construct")
        }
    }
    inner, err := parse_alt(p)
    if !err.ok do return nil, err
    if rpeek(p) != ')' do return nil, rerr(p, "missing ')'")
    radv(p)

    if non_capt {
        ng := new(Re_Node); ng.kind = .NonCaptGroup
        append(&ng.children, inner)
        return ng, Regex_Err{ ok = true }
    }
    // Capturing group. Assign index.
    p.group_counter += 1
    g := new(Re_Node)
    g.kind = .Group
    g.group_idx = p.group_counter
    g.group_name = name
    append(&p.group_names, strings.clone(name))
    append(&g.children, inner)
    return g, Regex_Err{ ok = true }
}

@(private="file")
parse_class :: proc(p: ^Re_Parser) -> (^Re_Node, Regex_Err) {
    radv(p)  // consume '['
    cc := new(Char_Class)
    if rpeek(p) == '^' {
        cc.negated = true
        radv(p)
    }
    // A leading ']' is treated as literal in some flavors ; we reject.
    if rpeek(p) == ']' do return nil, rerr(p, "empty character class")

    for {
        c := rpeek(p)
        if c == 0 do return nil, rerr(p, "unterminated class")
        if c == ']' { radv(p); break }
        // An atom : literal-rune, escape, or property. Then optional -range.
        lo_r, e1 := parse_class_atom(p, cc)
        if !e1.ok do return nil, e1
        // If lo_r < 0 it was a class-flag (\d, \p{L}) — no range.
        if lo_r >= 0 {
            if rpeek(p) == '-' && p.idx + 1 < len(p.src) && p.src[p.idx + 1] != ']' {
                radv(p)  // '-'
                hi_r, e2 := parse_class_atom(p, cc)
                if !e2.ok do return nil, e2
                if hi_r < lo_r do return nil, rerr(p, "class range hi < lo")
                append(&cc.ranges, Rune_Range{ lo_r, hi_r })
            } else {
                append(&cc.ranges, Rune_Range{ lo_r, lo_r })
            }
        }
    }

    n := new(Re_Node)
    n.kind = .CharClass
    n.class = cc
    return n, Regex_Err{ ok = true }
}

// Parse a single thing inside [...]. Returns a single rune (≥ 0) OR -1
// if the atom was a class-flag (\d, \p{L}) that has already been merged
// into cc.flags.
@(private="file")
parse_class_atom :: proc(p: ^Re_Parser, cc: ^Char_Class) -> (rune, Regex_Err) {
    c := rpeek(p)
    if c == '\\' {
        return parse_escape_for_class(p, cc)
    }
    r, sz := utf8_decode(p.src, p.idx)
    if sz == 0 do return 0, rerr(p, "bad rune in class")
    p.idx += sz
    return r, Regex_Err{ ok = true }
}

@(private="file")
parse_escape_for_class :: proc(p: ^Re_Parser, cc: ^Char_Class) -> (rune, Regex_Err) {
    radv(p)  // consume '\'
    c := rpeek(p)
    switch c {
    case 'd': radv(p); incl(&cc.flags, Char_Class_Flag.Ascii_Digit);     return -1, Regex_Err{ok=true}
    case 'D': radv(p); incl(&cc.flags, Char_Class_Flag.Not_Ascii_Digit); return -1, Regex_Err{ok=true}
    case 's': radv(p); incl(&cc.flags, Char_Class_Flag.Ascii_Space);     return -1, Regex_Err{ok=true}
    case 'S': radv(p); incl(&cc.flags, Char_Class_Flag.Not_Ascii_Space); return -1, Regex_Err{ok=true}
    case 'w': radv(p); incl(&cc.flags, Char_Class_Flag.Ascii_Word);      return -1, Regex_Err{ok=true}
    case 'W': radv(p); incl(&cc.flags, Char_Class_Flag.Not_Ascii_Word);  return -1, Regex_Err{ok=true}
    case 'p':
        radv(p)
        if rpeek(p) != '{' do return 0, rerr(p, "expected '{' after \\p")
        radv(p)
        name_sb := strings.builder_make(context.temp_allocator)
        for {
            k := rpeek(p)
            if k == '}' { radv(p); break }
            if k == 0 do return 0, rerr(p, "unterminated \\p{}")
            strings.write_byte(&name_sb, k)
            radv(p)
        }
        name := strings.to_string(name_sb)
        switch name {
        case "L", "Letter":      incl(&cc.flags, Char_Class_Flag.Unicode_Letter)
        case "N", "Number":      incl(&cc.flags, Char_Class_Flag.Unicode_Number)
        case "P", "Punct":       incl(&cc.flags, Char_Class_Flag.Unicode_Punct)
        case "S", "Symbol":      incl(&cc.flags, Char_Class_Flag.Unicode_Symbol)
        case: return 0, rerr(p, fmt.tprintf("unknown \\p{{%s}}", name))
        }
        return -1, Regex_Err{ ok = true }
    }
    // Single-char escape → literal rune.
    r := parse_simple_escape_rune(p)
    if r < 0 do return 0, rerr(p, "bad escape in class")
    return r, Regex_Err{ ok = true }
}

@(private="file")
parse_escape :: proc(p: ^Re_Parser) -> (^Re_Node, Regex_Err) {
    radv(p)  // '\'
    c := rpeek(p)
    switch c {
    case 'd', 'D', 's', 'S', 'w', 'W':
        // Predefined class outside [] : wrap in CharClass
        radv(p)
        cc := new(Char_Class)
        switch c {
        case 'd': incl(&cc.flags, Char_Class_Flag.Ascii_Digit)
        case 'D': incl(&cc.flags, Char_Class_Flag.Not_Ascii_Digit)
        case 's': incl(&cc.flags, Char_Class_Flag.Ascii_Space)
        case 'S': incl(&cc.flags, Char_Class_Flag.Not_Ascii_Space)
        case 'w': incl(&cc.flags, Char_Class_Flag.Ascii_Word)
        case 'W': incl(&cc.flags, Char_Class_Flag.Not_Ascii_Word)
        }
        n := new(Re_Node); n.kind = .CharClass; n.class = cc
        return n, Regex_Err{ ok = true }
    case 'p':
        radv(p)
        if rpeek(p) != '{' do return nil, rerr(p, "expected '{' after \\p")
        radv(p)
        name_sb := strings.builder_make(context.temp_allocator)
        for {
            k := rpeek(p)
            if k == '}' { radv(p); break }
            if k == 0 do return nil, rerr(p, "unterminated \\p{}")
            strings.write_byte(&name_sb, k)
            radv(p)
        }
        name := strings.to_string(name_sb)
        cc := new(Char_Class)
        switch name {
        case "L", "Letter":      incl(&cc.flags, Char_Class_Flag.Unicode_Letter)
        case "N", "Number":      incl(&cc.flags, Char_Class_Flag.Unicode_Number)
        case "P", "Punct":       incl(&cc.flags, Char_Class_Flag.Unicode_Punct)
        case "S", "Symbol":      incl(&cc.flags, Char_Class_Flag.Unicode_Symbol)
        case: return nil, rerr(p, fmt.tprintf("unknown \\p{{%s}}", name))
        }
        n := new(Re_Node); n.kind = .CharClass; n.class = cc
        return n, Regex_Err{ ok = true }
    case 'b':
        radv(p); n := new(Re_Node); n.kind = .Anchor_BOW; return n, Regex_Err{ ok = true }
    case 'B':
        radv(p); n := new(Re_Node); n.kind = .Anchor_NBOW; return n, Regex_Err{ ok = true }
    case 'k':
        // \k<name>
        radv(p)
        if rpeek(p) != '<' do return nil, rerr(p, "expected '<' after \\k")
        radv(p)
        name_sb := strings.builder_make()
        for {
            k := rpeek(p)
            if k == '>' { radv(p); break }
            if k == 0 do return nil, rerr(p, "unterminated \\k<>")
            strings.write_byte(&name_sb, k)
            radv(p)
        }
        name := strings.to_string(name_sb)
        idx := find_group_by_name(p, name)
        if idx < 0 do return nil, rerr(p, fmt.tprintf("unknown group name '%s'", name))
        n := new(Re_Node); n.kind = .Backref; n.backref = idx
        return n, Regex_Err{ ok = true }
    case '0'..='9':
        // numeric backref
        v := 0
        for rpeek(p) >= '0' && rpeek(p) <= '9' {
            v = v * 10 + int(rpeek(p) - '0')
            radv(p)
        }
        n := new(Re_Node); n.kind = .Backref; n.backref = v
        return n, Regex_Err{ ok = true }
    }
    // Simple-char escape.
    r := parse_simple_escape_rune(p)
    if r < 0 do return nil, rerr(p, "bad escape")
    n := new(Re_Node); n.kind = .Lit; n.rune_val = r
    return n, Regex_Err{ ok = true }
}

@(private="file")
parse_simple_escape_rune :: proc(p: ^Re_Parser) -> rune {
    c := rpeek(p)
    switch c {
    case 'n': radv(p); return '\n'
    case 't': radv(p); return '\t'
    case 'r': radv(p); return '\r'
    case 'f': radv(p); return '\f'
    case 'v': radv(p); return '\v'
    case '0': radv(p); return 0
    case 'a': radv(p); return 7
    case 'x':
        radv(p)
        if p.idx + 2 > len(p.src) do return -1
        hi := hex_nib(p.src[p.idx]);    p.idx += 1
        lo := hex_nib(p.src[p.idx]);    p.idx += 1
        if hi < 0 || lo < 0 do return -1
        return rune(hi * 16 + lo)
    case 'u':
        radv(p)
        if p.idx + 4 > len(p.src) do return -1
        v := 0
        for _ in 0 ..< 4 {
            d := hex_nib(p.src[p.idx]); p.idx += 1
            if d < 0 do return -1
            v = v*16 + d
        }
        return rune(v)
    }
    // Any other single character is treated as literal-escape of itself.
    r, sz := utf8_decode(p.src, p.idx)
    if sz == 0 do return -1
    p.idx += sz
    return r
}

@(private="file")
hex_nib :: proc(c: u8) -> int {
    switch {
    case c >= '0' && c <= '9': return int(c - '0')
    case c >= 'a' && c <= 'f': return int(c - 'a') + 10
    case c >= 'A' && c <= 'F': return int(c - 'A') + 10
    }
    return -1
}

@(private="file")
find_group_by_name :: proc(p: ^Re_Parser, name: string) -> int {
    for n, i in p.group_names {
        if i > 0 && n == name do return i
    }
    return -1
}

@(private="file")
incl :: #force_inline proc(s: ^bit_set[Char_Class_Flag], f: Char_Class_Flag) {
    s^ = s^ + {f}
}
