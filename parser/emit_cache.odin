package cslparser

// § CSLv3 EMIT CACHE (T28.a Session-10)
// I> incremental-emit : BLAKE3(source-text + target + schema-version) → bytes
// I> location : .emit-cache/<hash[:2]>/<hash[2:]>.json
// I> LRU-eviction : 50MB soft-cap (Session-11 to implement ; for now append-only)
// I> cache entry : bytes + source-map + cert + schema-version + timestamp
// R! ← matches smt_cache sharded-layout pattern

import "core:crypto/hash"
import "core:fmt"
import "core:os"
import "core:strings"

Emit_Cache_Entry :: struct {
    bytes:          string,
    source_map:     string,
    cert:           string,
    target:         Emit_Target,
    schema_version: string,
    created_ms:     int,
}

@(private="file")
EMIT_CACHE_DIR :: ".emit-cache"

emit_cache_key :: proc(ctx: ^Emit_Context) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, ctx.source_text)
    strings.write_byte(&sb, '|')
    strings.write_string(&sb, emit_target_name(ctx.target))
    strings.write_byte(&sb, '|')
    strings.write_string(&sb, schema_version_for(ctx.target))
    strings.write_byte(&sb, '|')
    // config-hash : source_map + sign + standalone together
    strings.write_string(&sb, fmt.tprintf("sm=%t:sign=%t:sa=%t",
        ctx.config.source_map, ctx.config.sign, ctx.config.standalone))
    canonical := strings.to_string(sb)
    return blake3_hex_of_string(canonical)
}

@(private="file")
blake3_hex_of_string :: proc(s: string) -> string {
    digest := hash.hash_string(.BLAKE2B, s)
    defer delete(digest)
    sb := strings.builder_make()
    for b in digest do strings.write_string(&sb, fmt.tprintf("%02x", b))
    return strings.to_string(sb)
}

emit_cache_init :: proc() -> bool {
    if !os.exists(EMIT_CACHE_DIR) {
        if os.make_directory(EMIT_CACHE_DIR) != 0 do return false
    }
    return true
}

@(private="file")
cache_path :: proc(hash_: string) -> string {
    if len(hash_) < 3 do return fmt.tprintf("%s/%s.json", EMIT_CACHE_DIR, hash_)
    return fmt.tprintf("%s/%s/%s.json", EMIT_CACHE_DIR, hash_[:2], hash_[2:])
}

emit_cache_lookup :: proc(key: string) -> (Emit_Cache_Entry, bool) {
    path := cache_path(key)
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil do return Emit_Cache_Entry{}, false
    defer delete(data, context.allocator)
    return parse_entry(string(data))
}

emit_cache_store :: proc(key: string, entry: Emit_Cache_Entry) -> bool {
    if !emit_cache_init() do return false
    if len(key) >= 2 {
        shard := fmt.tprintf("%s/%s", EMIT_CACHE_DIR, key[:2])
        if !os.exists(shard) {
            if os.make_directory(shard) != 0 do return false
        }
    }
    path := cache_path(key)
    local := entry
    body := serialize_entry(&local)
    defer delete(body)
    return os.write_entire_file(path, transmute([]byte)body) == nil
}

@(private="file")
serialize_entry :: proc(e: ^Emit_Cache_Entry) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, "{\n")
    strings.write_string(&sb, fmt.tprintf("  \"schema_version\": %q,\n", e.schema_version))
    strings.write_string(&sb, fmt.tprintf("  \"target\": %q,\n", emit_target_name(e.target)))
    strings.write_string(&sb, fmt.tprintf("  \"created_ms\": %d,\n", e.created_ms))
    strings.write_string(&sb, fmt.tprintf("  \"cert\": %q,\n", e.cert))
    strings.write_string(&sb, fmt.tprintf("  \"source_map_len\": %d,\n", len(e.source_map)))
    strings.write_string(&sb, fmt.tprintf("  \"body_len\": %d,\n", len(e.bytes)))
    strings.write_string(&sb, "  \"body\": ")
    write_json_quoted(&sb, e.bytes)
    strings.write_string(&sb, ",\n  \"source_map\": ")
    write_json_quoted(&sb, e.source_map)
    strings.write_string(&sb, "\n}\n")
    return strings.to_string(sb)
}

@(private="file")
write_json_quoted :: proc(sb: ^strings.Builder, s: string) {
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
parse_entry :: proc(text: string) -> (Emit_Cache_Entry, bool) {
    // Small hand-roll : find keys and extract values. Complete JSON-parse
    // overhead not worth the dependency for cache-read.
    e: Emit_Cache_Entry
    e.bytes          = extract_json_string(text, "\"body\":")
    e.source_map     = extract_json_string(text, "\"source_map\":")
    e.cert           = extract_json_string(text, "\"cert\":")
    e.schema_version = extract_json_string(text, "\"schema_version\":")
    tgt := extract_json_string(text, "\"target\":")
    if t, ok := emit_target_parse(tgt); ok do e.target = t
    e.created_ms = extract_json_int(text, "\"created_ms\":")
    return e, len(e.bytes) > 0 || len(e.schema_version) > 0
}

@(private="file")
extract_json_string :: proc(text, key: string) -> string {
    idx := strings.index(text, key)
    if idx < 0 do return ""
    rest := text[idx + len(key):]
    rest = strings.trim_left_space(rest)
    if len(rest) == 0 || rest[0] != '"' do return ""
    rest = rest[1:]
    // walk with escape handling
    sb := strings.builder_make()
    i := 0
    for i < len(rest) {
        c := rest[i]
        if c == '\\' && i + 1 < len(rest) {
            switch rest[i+1] {
            case '"':  strings.write_byte(&sb, '"')
            case '\\': strings.write_byte(&sb, '\\')
            case 'n':  strings.write_byte(&sb, '\n')
            case 'r':  strings.write_byte(&sb, '\r')
            case 't':  strings.write_byte(&sb, '\t')
            case:      strings.write_byte(&sb, rest[i+1])
            }
            i += 2
            continue
        }
        if c == '"' do break
        strings.write_byte(&sb, c)
        i += 1
    }
    return strings.to_string(sb)
}

@(private="file")
extract_json_int :: proc(text, key: string) -> int {
    idx := strings.index(text, key)
    if idx < 0 do return 0
    rest := text[idx + len(key):]
    rest = strings.trim_left_space(rest)
    n := 0
    i := 0
    for i < len(rest) && rest[i] >= '0' && rest[i] <= '9' {
        n = n * 10 + int(rest[i] - '0')
        i += 1
    }
    return n
}
