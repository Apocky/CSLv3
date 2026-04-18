package cslparser

// § A8 Session-15 : public regex API ; orchestrates parse → compile → VM.
//
// API :
//   Regex + Regex_Err           (defined in regex_parse.odin)
//   regex_compile(pattern)   → (Regex, Regex_Err)
//   regex_match(re, input)   → Regex_Match         anchored-at-start scan
//   regex_search(re, input)  → Regex_Match         scan any start position
//   regex_find_all(re, input)→ []Regex_Match
//   regex_replace(re, input, template) → string   $1 $2 $<name>
//   regex_free(re)           → free bytecode + AST
//   regex_selftest()         → run 30+ vectors
//
// CLI-flags (main.odin) :
//   --regex-match <pat> <inp>
//   --regex-find  <pat> <inp>
//   --regex-replace <pat> <repl> <inp>
//   --regex-selftest
//   --regex-compile-check <pat>

import "core:fmt"
import "core:os"
import "core:strings"

// Opaque compiled regex.
Regex :: struct {
    ast:   ^Re_Node,                     // kept for re-compile/diagnostics
    prog:  Regex_Program,
    pattern_text: string,                // copy of the source pattern
}

// ------------------------- compile -------------------------

regex_compile :: proc(pattern: string, allocator := context.allocator) -> (Regex, Regex_Err) {
    context.allocator = allocator
    root, perr := regex_parse_pattern(pattern)
    if !perr.ok do return Regex{}, perr
    prog := regex_compile_ast(root, _collect_group_names(root))
    return Regex{
        ast = root,
        prog = prog,
        pattern_text = strings.clone(pattern),
    }, Regex_Err{ ok = true }
}

regex_free :: proc(re: ^Regex) {
    // AST + class descriptors are allocated per parse ; leave to allocator
    // lifetime. For an explicit deep-free walkers could be added.
    delete(re.prog.code)
    for n in re.prog.group_names do delete(n)
    delete(re.prog.group_names)
    delete(re.pattern_text)
}

// Recursively collect group names in group-index order. Index 0 is the
// whole-match (empty name). Index k is k-th encountered capturing group.
@(private="file")
_collect_group_names :: proc(root: ^Re_Node) -> []string {
    names: [dynamic]string
    append(&names, strings.clone(""))
    _walk_groups(&names, root)
    return names[:]
}

@(private="file")
_walk_groups :: proc(names: ^[dynamic]string, n: ^Re_Node) {
    if n == nil do return
    if n.kind == .Group {
        for len(names) <= n.group_idx do append(names, strings.clone(""))
        if len(n.group_name) > 0 do names[n.group_idx] = strings.clone(n.group_name)
    }
    for c in n.children do _walk_groups(names, c)
}

// ------------------------- matching -------------------------

// Anchored match from position 0.
regex_match :: proc(re: ^Regex, input: string) -> Regex_Match {
    return regex_nfa_run(&re.prog, input, 0)
}

// Scan across the input ; return the first match at any position.
regex_search :: proc(re: ^Regex, input: string) -> Regex_Match {
    // Walk by byte since utf8 continuation bytes would just cause the VM
    // to find nothing anyway ; start-positions are at rune boundaries.
    i := 0
    for i <= len(input) {
        m := regex_nfa_run(&re.prog, input, i)
        if m.ok do return m
        // Advance one rune.
        _, rn := utf8_decode(input, i)
        if rn == 0 { i += 1; continue }
        i += rn
    }
    return Regex_Match{ ok = false, start = -1, end = -1 }
}

// All non-overlapping matches.
regex_find_all :: proc(re: ^Regex, input: string,
                        allocator := context.allocator) -> []Regex_Match {
    context.allocator = allocator
    out: [dynamic]Regex_Match
    i := 0
    for i <= len(input) {
        m := regex_nfa_run(&re.prog, input, i)
        if m.ok {
            append(&out, m)
            if m.end == m.start {
                // zero-width match ; advance one rune to avoid infinite loop
                _, rn := utf8_decode(input, i)
                if rn == 0 do break
                i += rn
            } else {
                i = m.end
            }
        } else {
            _, rn := utf8_decode(input, i)
            if rn == 0 do break
            i += rn
        }
    }
    return out[:]
}

// ------------------------- replace -------------------------

// Template substitution : $0 = whole match, $1..$n = groups, $<name> = named.
regex_replace :: proc(re: ^Regex, input: string, template: string,
                      allocator := context.allocator) -> string {
    context.allocator = allocator
    matches := regex_find_all(re, input)
    defer delete(matches)
    sb := strings.builder_make()
    last := 0
    for &m in matches {
        strings.write_string(&sb, input[last:m.start])
        _apply_template(&sb, template, &m, input)
        last = m.end
    }
    strings.write_string(&sb, input[last:])
    return strings.to_string(sb)
}

@(private="file")
_apply_template :: proc(sb: ^strings.Builder, tpl: string, m: ^Regex_Match, input: string) {
    i := 0
    for i < len(tpl) {
        c := tpl[i]
        if c != '$' {
            strings.write_byte(sb, c)
            i += 1
            continue
        }
        // '$' escape
        if i + 1 >= len(tpl) {
            strings.write_byte(sb, '$')
            i += 1
            continue
        }
        nc := tpl[i + 1]
        if nc == '$' {
            strings.write_byte(sb, '$')
            i += 2
            continue
        }
        if nc >= '0' && nc <= '9' {
            // parse number (one or two digits)
            n := int(nc - '0')
            if i + 2 < len(tpl) && tpl[i + 2] >= '0' && tpl[i + 2] <= '9' {
                n = n * 10 + int(tpl[i + 2] - '0')
                i += 3
            } else {
                i += 2
            }
            if n < len(m.groups) {
                g := m.groups[n]
                strings.write_string(sb, g.text)
            }
            continue
        }
        if nc == '<' {
            // $<name>
            j := i + 2
            for j < len(tpl) && tpl[j] != '>' { j += 1 }
            if j >= len(tpl) {
                strings.write_string(sb, tpl[i:])
                return
            }
            name := tpl[i+2:j]
            for g in m.groups {
                if g.name == name {
                    strings.write_string(sb, g.text)
                    break
                }
            }
            i = j + 1
            continue
        }
        // Unknown escape : emit literally
        strings.write_byte(sb, c)
        i += 1
    }
}

// ------------------------- selftest -------------------------

regex_selftest :: proc() {
    ok_n, fail_n := 0, 0
    check_match :: proc(name, pat, inp: string, want_ok: bool, fail: ^int, ok_c: ^int) {
        re, pe := regex_compile(pat)
        if !pe.ok {
            fmt.printf("%-26s COMPILE-FAIL : %s\n", name, pe.msg)
            fail^ += 1
            return
        }
        defer regex_free(&re)
        m := regex_search(&re, inp)
        got := m.ok
        mark := "OK"
        if got != want_ok { mark = "FAIL"; fail^ += 1 } else { ok_c^ += 1 }
        fmt.printf("%-26s %s  pat=%-18s inp=%q\n", name, mark, pat, inp)
    }

    check_span :: proc(name, pat, inp, want: string, fail: ^int, ok_c: ^int) {
        re, pe := regex_compile(pat)
        if !pe.ok {
            fmt.printf("%-26s COMPILE-FAIL : %s\n", name, pe.msg)
            fail^ += 1
            return
        }
        defer regex_free(&re)
        m := regex_search(&re, inp)
        got := ""
        if m.ok do got = inp[m.start:m.end]
        mark := "OK"
        if got != want { mark = "FAIL"; fail^ += 1 } else { ok_c^ += 1 }
        fmt.printf("%-26s %s  pat=%-18s got=%q\n", name, mark, pat, got)
    }

    // literal
    check_match("literal-full",       "abc",       "abc",      true,  &fail_n, &ok_n)
    check_match("literal-partial",    "abc",       "xabcy",    true,  &fail_n, &ok_n)
    check_match("literal-no-match",   "abc",       "aXc",      false, &fail_n, &ok_n)
    // escape
    check_match("escape-dot",         "\\.",        ".",        true,  &fail_n, &ok_n)
    check_match("escape-pipe",        "a\\|b",      "a|b",      true,  &fail_n, &ok_n)
    // char class
    check_match("class-range",        "[a-z]",     "x",        true,  &fail_n, &ok_n)
    check_match("class-negated",      "[^0-9]",    "a",        true,  &fail_n, &ok_n)
    check_match("class-digit",        "\\d",        "5",        true,  &fail_n, &ok_n)
    check_match("class-word",         "\\w",        "foo_1",    true,  &fail_n, &ok_n)
    // Unicode
    check_match("unicode-letter-CJK", "\\p{L}",     "中",       true,  &fail_n, &ok_n)
    check_match("unicode-number",     "\\p{N}",     "5",        true,  &fail_n, &ok_n)
    check_match("unicode-symbol",     "\\p{S}",     "⊗",        true,  &fail_n, &ok_n)
    // quantifiers
    check_match("star-empty",         "a*",        "",         true,  &fail_n, &ok_n)
    check_match("star-many",          "^a*$",      "aaaa",     true,  &fail_n, &ok_n)
    check_match("plus-empty-no",      "^a+$",      "",         false, &fail_n, &ok_n)
    check_match("quant-exact",        "^a{3}$",    "aaa",      true,  &fail_n, &ok_n)
    check_match("quant-range-in",     "^a{2,4}$",  "aaa",      true,  &fail_n, &ok_n)
    check_match("quant-range-out",    "^a{2,4}$",  "a",        false, &fail_n, &ok_n)
    // lazy
    check_span ("lazy-shortest",      "a+?",       "aaaa",     "a",    &fail_n, &ok_n)
    check_span ("greedy-longest",     "a+",        "aaaa",     "aaaa", &fail_n, &ok_n)
    // anchors
    check_match("anchor-bos",         "^abc",      "abcde",    true,  &fail_n, &ok_n)
    check_match("anchor-bos-fail",    "^abc",      "xabc",     false, &fail_n, &ok_n)
    check_match("anchor-eos",         "abc$",      "xabc",     true,  &fail_n, &ok_n)
    check_match("word-boundary",      "\\babc",    "abc def",  true,  &fail_n, &ok_n)
    // alternation
    check_match("alt-cat",            "cat|dog",   "cat",      true,  &fail_n, &ok_n)
    check_match("alt-dog",            "cat|dog",   "dog",      true,  &fail_n, &ok_n)
    check_match("alt-miss",           "cat|dog",   "bird",     false, &fail_n, &ok_n)
    // groups + capture
    {
        re, _ := regex_compile("(abc)")
        m := regex_search(&re, "abc")
        name := "group-1-capture"
        exp := "abc"
        got := (len(m.groups) > 1) ? m.groups[1].text : ""
        if got != exp { fmt.printf("%-26s FAIL (got %q)\n", name, got); fail_n += 1 }
        else          { fmt.printf("%-26s OK\n", name); ok_n += 1 }
        regex_free(&re)
    }
    {
        re, _ := regex_compile("(?:abc)")
        m := regex_search(&re, "abc")
        name := "noncapt-group"
        n_groups := len(m.groups) - 1   // minus whole-match
        if n_groups != 0 { fmt.printf("%-26s FAIL (n=%d)\n", name, n_groups); fail_n += 1 }
        else             { fmt.printf("%-26s OK\n", name); ok_n += 1 }
        regex_free(&re)
    }
    {
        re, _ := regex_compile("(?<word>[a-z]+)")
        m := regex_search(&re, "hello world")
        got := ""
        for g in m.groups do if g.name == "word" do got = g.text
        exp := "hello"
        name := "named-group"
        if got != exp { fmt.printf("%-26s FAIL (got %q)\n", name, got); fail_n += 1 }
        else          { fmt.printf("%-26s OK\n", name); ok_n += 1 }
        regex_free(&re)
    }
    // backref
    check_match("backref-match",      "^(.)\\1$",   "aa",       true,  &fail_n, &ok_n)
    check_match("backref-miss",       "^(.)\\1$",   "ab",       false, &fail_n, &ok_n)
    // find-all
    {
        re, _ := regex_compile("\\d+")
        matches := regex_find_all(&re, "a1b22c333")
        got := ""
        for m in matches {
            if len(got) > 0 do got = fmt.tprintf("%s,%s", got, got_span(m, "a1b22c333"))
            else            do got = got_span(m, "a1b22c333")
        }
        exp := "1,22,333"
        name := "find-all-digits"
        if got != exp { fmt.printf("%-26s FAIL (got %q)\n", name, got); fail_n += 1 }
        else          { fmt.printf("%-26s OK\n", name); ok_n += 1 }
        regex_free(&re)
    }
    // replace
    {
        re, _ := regex_compile("a+")
        out := regex_replace(&re, "aaabaaa", "X")
        exp := "XbX"
        name := "replace-plain"
        if out != exp { fmt.printf("%-26s FAIL (got %q)\n", name, out); fail_n += 1 }
        else          { fmt.printf("%-26s OK\n", name); ok_n += 1 }
        regex_free(&re)
    }
    {
        re, _ := regex_compile("(\\w+)")
        out := regex_replace(&re, "foo", "<$1>")
        exp := "<foo>"
        name := "replace-backref"
        if out != exp { fmt.printf("%-26s FAIL (got %q)\n", name, out); fail_n += 1 }
        else          { fmt.printf("%-26s OK\n", name); ok_n += 1 }
        regex_free(&re)
    }
    // Apocky-specific
    check_match("cslv3-morpheme",     "'[dfsmtepgr]", "'d",     true, &fail_n, &ok_n)
    check_match("cslv3-section",      "§+",           "§§§",   true, &fail_n, &ok_n)
    check_match("cslv3-operator",     "[⊑⊗→]",        "⊗",      true, &fail_n, &ok_n)

    total := ok_n + fail_n
    fmt.printf("§ regex selftest : %d ok / %d fail (total %d)\n", ok_n, fail_n, total)
    if fail_n > 0 do os.exit(1)
    os.exit(0)
}

@(private="file")
got_span :: proc(m: Regex_Match, input: string) -> string {
    if !m.ok do return ""
    return input[m.start:m.end]
}
