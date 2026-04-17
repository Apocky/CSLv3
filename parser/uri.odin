package cslparser

// § A7 Session-14 : RFC 3986 URI parser (bespoke Odin).
//
// I> replaces : rust `url` + `percent-encoding` + `idna` stack (D17-D19).
//    Together those pull in 6+ transitive crates (icu-normalizer,
//    icu-properties, idna_adapter, ...) — eliminating them cuts a
//    large slice off the LSP build tree.
// I> scope : RFC 3986 §§3-6 generic-syntax parser + percent-encode/decode.
//            Punycode/IDNA is deferred (intentionally) — ASCII host only.
//            That's sufficient for LSP file:// URIs which are the main
//            consumer.
// I> ~300 LOC (under phase-A estimate) ← grammar is regular
//
// API :
//   uri_parse(s) -> (URI, ok)           split into scheme/auth/path/query/frag
//   uri_encode(s) -> string             percent-encode reserved chars
//   uri_decode(s) -> (string, ok)       percent-decode
//   uri_selftest()                       RFC 3986 appendix-C + extras
//
// CLI :
//   parser.exe --uri-parse <uri>        prints component breakdown + exit 0
//   parser.exe --uri-selftest           runs selftest vectors
//
// Spec-cite : RFC 3986 (January 2005).

import "core:fmt"
import "core:os"
import "core:strings"

URI :: struct {
    raw       : string,    // original input
    scheme    : string,    // e.g. "https"
    authority : string,    // e.g. "user:pass@host:port"  ; may be empty
    userinfo  : string,    // split from authority if present
    host      : string,    // bare host ; IPv6 retains []
    port      : string,    // as text (empty = scheme default)
    path      : string,    // e.g. "/foo/bar"
    query     : string,    // after '?' ; empty if absent
    fragment  : string,    // after '#' ; empty if absent
    has_authority : bool,
}

uri_parse :: proc(input: string) -> (URI, bool) {
    u: URI
    u.raw = input
    s := input
    // 1. scheme ← letter followed by letter/digit/+/-/.
    i := 0
    if len(s) > 0 && is_alpha(s[0]) {
        for i < len(s) {
            c := s[i]
            if is_alpha(c) || is_digit(c) || c == '+' || c == '-' || c == '.' { i += 1 }
            else do break
        }
        if i < len(s) && s[i] == ':' {
            u.scheme = s[:i]
            s = s[i+1:]
        } else {
            // no scheme ; treat whole string as path/relative ref
            s = input
            u.scheme = ""
        }
    }
    // 2. authority ← "//" auth
    if len(s) >= 2 && s[:2] == "//" {
        s = s[2:]
        // authority ends at first '/' '?' '#' or EOF
        end := len(s)
        for i in 0 ..< len(s) {
            c := s[i]
            if c == '/' || c == '?' || c == '#' { end = i; break }
        }
        u.authority = s[:end]
        u.has_authority = true
        parse_authority(&u)
        s = s[end:]
    }
    // 3. path ← up to '?' or '#'
    path_end := len(s)
    for i in 0 ..< len(s) {
        c := s[i]
        if c == '?' || c == '#' { path_end = i; break }
    }
    u.path = s[:path_end]
    s = s[path_end:]
    // 4. query ← '?' up to '#'
    if len(s) > 0 && s[0] == '?' {
        s = s[1:]
        q_end := len(s)
        for i in 0 ..< len(s) {
            if s[i] == '#' { q_end = i; break }
        }
        u.query = s[:q_end]
        s = s[q_end:]
    }
    // 5. fragment ← '#' rest
    if len(s) > 0 && s[0] == '#' {
        u.fragment = s[1:]
    }
    return u, true
}

@(private="file")
parse_authority :: proc(u: ^URI) {
    s := u.authority
    // userinfo : part before '@' if '@' appears before ':' that delimits port
    at := -1
    for i in 0 ..< len(s) {
        if s[i] == '@' { at = i; break }
    }
    host_start := 0
    if at >= 0 {
        u.userinfo = s[:at]
        host_start = at + 1
    }
    rest := s[host_start:]
    // IPv6 literal ← "[...]"
    if len(rest) > 0 && rest[0] == '[' {
        close := strings.index_byte(rest, ']')
        if close >= 0 {
            u.host = rest[:close + 1]
            rest = rest[close + 1:]
            if len(rest) > 0 && rest[0] == ':' {
                u.port = rest[1:]
            }
            return
        }
    }
    // host : up to ':' or end
    colon := strings.index_byte(rest, ':')
    if colon >= 0 {
        u.host = rest[:colon]
        u.port = rest[colon + 1:]
    } else {
        u.host = rest
    }
}

@(private="file")
is_alpha :: #force_inline proc "contextless" (c: u8) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
}

@(private="file")
is_digit :: #force_inline proc "contextless" (c: u8) -> bool {
    return c >= '0' && c <= '9'
}

@(private="file")
is_unreserved :: #force_inline proc "contextless" (c: u8) -> bool {
    return is_alpha(c) || is_digit(c) || c == '-' || c == '.' || c == '_' || c == '~'
}

// Percent-encoding ← RFC 3986 §2.1
// Encodes everything outside the unreserved set.
uri_encode :: proc(s: string, allocator := context.allocator) -> string {
    context.allocator = allocator
    sb := strings.builder_make()
    HEX := "0123456789ABCDEF"
    for i in 0 ..< len(s) {
        c := s[i]
        if is_unreserved(c) {
            strings.write_byte(&sb, c)
        } else {
            strings.write_byte(&sb, '%')
            strings.write_byte(&sb, HEX[c >> 4])
            strings.write_byte(&sb, HEX[c & 0xf])
        }
    }
    return strings.to_string(sb)
}

uri_decode :: proc(s: string, allocator := context.allocator) -> (string, bool) {
    context.allocator = allocator
    sb := strings.builder_make()
    i := 0
    for i < len(s) {
        c := s[i]
        if c == '%' {
            if i + 2 >= len(s) {
                strings.builder_destroy(&sb)
                return "", false
            }
            h := hex_nibble_uri(s[i + 1])
            l := hex_nibble_uri(s[i + 2])
            if h < 0 || l < 0 {
                strings.builder_destroy(&sb)
                return "", false
            }
            strings.write_byte(&sb, u8(h * 16 + l))
            i += 3
        } else if c == '+' {
            // application/x-www-form-urlencoded decodes '+' as space.
            // Generic URI decode leaves '+' as-is ; callers that want
            // form-decoding should do a '+' → ' ' pass first. Leaving as '+'.
            strings.write_byte(&sb, c)
            i += 1
        } else {
            strings.write_byte(&sb, c)
            i += 1
        }
    }
    return strings.to_string(sb), true
}

@(private="file")
hex_nibble_uri :: proc(c: u8) -> int {
    if c >= '0' && c <= '9' do return int(c - '0')
    if c >= 'a' && c <= 'f' do return int(c - 'a' + 10)
    if c >= 'A' && c <= 'F' do return int(c - 'A' + 10)
    return -1
}

// ---------- selftest ----------
uri_selftest :: proc() {
    // Vector set : RFC 3986 Appendix C-style cases + common LSP file:// URIs.
    Case :: struct {
        name, input, scheme, userinfo, host, port, path, query, fragment: string,
        has_auth: bool,
    }
    cases := []Case{
        // common HTTPS
        {"https-simple", "https://example.com/foo",
         "https", "", "example.com", "", "/foo", "", "", true},
        {"https-port", "https://example.com:8080/foo/bar?q=1#frag",
         "https", "", "example.com", "8080", "/foo/bar", "q=1", "frag", true},
        {"https-auth", "https://user:pass@host.example/path",
         "https", "user:pass", "host.example", "", "/path", "", "", true},
        {"file-path", "file:///C:/Users/Apocky/x.txt",
         "file", "", "", "", "/C:/Users/Apocky/x.txt", "", "", true},
        {"file-unix", "file:///home/user/doc",
         "file", "", "", "", "/home/user/doc", "", "", true},
        {"urn-no-auth", "urn:ietf:rfc:3986",
         "urn", "", "", "", "ietf:rfc:3986", "", "", false},
        {"mailto", "mailto:feedback@cssl.dev",
         "mailto", "", "", "", "feedback@cssl.dev", "", "", false},
        {"ipv6", "https://[::1]:8080/api",
         "https", "", "[::1]", "8080", "/api", "", "", true},
        {"relative", "/foo/bar?q=x",
         "", "", "", "", "/foo/bar", "q=x", "", false},
        {"fragment-only", "#frag",
         "", "", "", "", "", "", "frag", false},
    }
    fail := 0
    for c in cases {
        u, ok := uri_parse(c.input)
        if !ok {
            fmt.printf("%-15s parse-FAIL\n", c.name)
            fail += 1; continue
        }
        mism := false
        if u.scheme != c.scheme { mism = true }
        if u.userinfo != c.userinfo { mism = true }
        if u.host != c.host { mism = true }
        if u.port != c.port { mism = true }
        if u.path != c.path { mism = true }
        if u.query != c.query { mism = true }
        if u.fragment != c.fragment { mism = true }
        if u.has_authority != c.has_auth { mism = true }
        mark := "OK"
        if mism { mark = "FAIL"; fail += 1 }
        fmt.printf("%-15s %s\n", c.name, mark)
        if mism {
            fmt.printf("  got  : scheme=%q userinfo=%q host=%q port=%q path=%q query=%q frag=%q auth=%v\n",
                u.scheme, u.userinfo, u.host, u.port, u.path, u.query, u.fragment, u.has_authority)
            fmt.printf("  want : scheme=%q userinfo=%q host=%q port=%q path=%q query=%q frag=%q auth=%v\n",
                c.scheme, c.userinfo, c.host, c.port, c.path, c.query, c.fragment, c.has_auth)
        }
    }

    // Percent-encode/decode round-trips
    enc_cases := []struct{ name, input, want_enc: string }{
        {"enc-space",  "hello world", "hello%20world"},
        {"enc-unicode-as-utf8", "café", "caf%C3%A9"},   // UTF-8 bytes
        {"enc-slashes", "/a/b c", "%2Fa%2Fb%20c"},
    }
    for ec in enc_cases {
        enc := uri_encode(ec.input, context.temp_allocator)
        dec, ok := uri_decode(enc, context.temp_allocator)
        mark := "OK"
        if enc != ec.want_enc || !ok || dec != ec.input {
            mark = "FAIL"; fail += 1
        }
        fmt.printf("%-25s %s\n", ec.name, mark)
        if mark == "FAIL" {
            fmt.printf("  enc got =%q want=%q\n  dec got =%q want=%q\n",
                enc, ec.want_enc, dec, ec.input)
        }
    }

    if fail == 0 {
        fmt.printf("§ URI selftest : all vectors verified\n")
        os.exit(0)
    } else {
        fmt.printf("§ URI selftest : %d failures\n", fail)
        os.exit(1)
    }
}
