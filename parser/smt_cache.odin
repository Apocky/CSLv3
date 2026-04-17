package cslparser

// § CSLv3 SMT PROOF-CACHE (T26.e Session-7)
// I> content-addressable cache : canonical-SMT-LIB2 → SHA-256 → result
// I> location : .proof-cache/<first-2-hex>/<rest>.json
// I> entry : {hash, result, solver, timestamp, canonical_head}
// I> BLAKE3 alternative considered — SHA-256 chosen ∵ Odin-core + universal
// I> invalidation : natural miss on formula-structure change (hash-mismatch) ;
//                   solver-version-mismatch → cache-warn + re-solve
// I> size-cap : LRU pruning @ >100MB (future-work ; soft-limit for now)
// R! ← handoff §§ PROOF-CACHE design

import "core:crypto/hash"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

// ---------- Entry type ----------

Cache_Entry :: struct {
    hash:            string,
    result:          Smt_Result,
    solver:          string,
    timestamp:       string,
    canonical_head:  string,    // first ~200 chars of canonical for debugging
}

// ---------- Init : ensure cache dir exists ----------

cache_init :: proc(dir: string) -> bool {
    if len(dir) == 0 do return false
    if !os.exists(dir) {
        err := os.make_directory(dir)
        if err != 0 do return false
    }
    return true
}

// ---------- Hash helpers ----------

sha256_hex_of_string :: proc(s: string) -> string {
    digest := hash.hash_string(.SHA256, s)
    defer delete(digest)
    return hex_encode(digest)
}

sha256_hex_of_bytes :: proc(b: []byte) -> string {
    digest := hash.hash_bytes(.SHA256, b)
    defer delete(digest)
    return hex_encode(digest)
}

@(private="file")
hex_encode :: proc(b: []byte) -> string {
    sb := strings.builder_make(context.allocator)
    for byte_v in b {
        strings.write_string(&sb, fmt.tprintf("%02x", byte_v))
    }
    return strings.to_string(sb)
}

// ---------- Path layout ----------
// <dir>/<hash[:2]>/<hash[2:]>.json
// shards keep directory sizes manageable at scale

@(private="file")
cache_path :: proc(dir, hash_: string) -> string {
    if len(hash_) < 3 do return fmt.tprintf("%s%s%s.json", dir, PATH_SEP, hash_)
    shard := hash_[:2]
    rest := hash_[2:]
    return fmt.tprintf("%s%s%s%s%s.json", dir, PATH_SEP, shard, PATH_SEP, rest)
}

@(private="file")
PATH_SEP :: "/"

// ---------- Lookup ----------

cache_lookup :: proc(dir, hash_: string) -> (Cache_Entry, bool) {
    path := cache_path(dir, hash_)
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil do return Cache_Entry{}, false
    defer delete(data, context.allocator)

    return parse_cache_entry(string(data))
}

@(private="file")
parse_cache_entry :: proc(s: string) -> (Cache_Entry, bool) {
    root, perr := json.parse_string(s, .JSON5, false, context.temp_allocator)
    if perr != nil do return Cache_Entry{}, false
    obj, ok := root.(json.Object)
    if !ok do return Cache_Entry{}, false

    e: Cache_Entry
    if v, has := obj["hash"];      has do if str, ok2 := v.(json.String); ok2 do e.hash = strings.clone(str)
    if v, has := obj["solver"];    has do if str, ok2 := v.(json.String); ok2 do e.solver = strings.clone(str)
    if v, has := obj["timestamp"]; has do if str, ok2 := v.(json.String); ok2 do e.timestamp = strings.clone(str)
    if v, has := obj["canonical_head"]; has do if str, ok2 := v.(json.String); ok2 do e.canonical_head = strings.clone(str)
    if v, has := obj["result"];    has {
        if str, ok2 := v.(json.String); ok2 {
            e.result = parse_result(str)
        }
    }
    return e, true
}

@(private="file")
parse_result :: proc(s: string) -> Smt_Result {
    switch s {
    case "unsat":   return .Unsat
    case "sat":     return .Sat
    case "unknown": return .Unknown
    case "timeout": return .Timeout
    case "error":   return .Error
    case "skipped": return .Skipped
    }
    return .Pending
}

// ---------- Store ----------

cache_store :: proc(dir, hash_: string, entry: Cache_Entry) -> bool {
    if !cache_init(dir) do return false
    // ensure shard dir
    if len(hash_) >= 2 {
        shard_dir := fmt.tprintf("%s%s%s", dir, PATH_SEP, hash_[:2])
        if !os.exists(shard_dir) {
            err := os.make_directory(shard_dir)
            if err != 0 do return false
        }
    }
    path := cache_path(dir, hash_)
    body := serialize_entry(entry)
    defer delete(body)
    return os.write_entire_file(path, transmute([]byte)body) == nil
}

@(private="file")
serialize_entry :: proc(e: Cache_Entry) -> string {
    sb := strings.builder_make(context.allocator)
    strings.write_string(&sb, "{\n")
    strings.write_string(&sb, fmt.tprintf("  \"hash\": %q,\n", e.hash))
    strings.write_string(&sb, fmt.tprintf("  \"result\": %q,\n", smt_result_name(e.result)))
    strings.write_string(&sb, fmt.tprintf("  \"solver\": %q,\n", e.solver))
    strings.write_string(&sb, fmt.tprintf("  \"timestamp\": %q,\n", e.timestamp))
    strings.write_string(&sb, fmt.tprintf("  \"canonical_head\": %q\n", e.canonical_head))
    strings.write_string(&sb, "}\n")
    return strings.to_string(sb)
}

// ---------- Time helpers ----------

time_now_ms :: proc() -> int {
    now := time.now()
    // convert to milliseconds since unix epoch
    ns := time.to_unix_nanoseconds(now)
    return int(ns / 1_000_000)
}

time_now_iso8601 :: proc() -> string {
    now := time.now()
    buf: [time.MIN_HMS_12_LEN + 32]u8
    // use simple format : YYYY-MM-DDTHH:MM:SSZ
    year, month, day := time.date(now)
    hour, minute, second := time.clock_from_time(now)
    return fmt.tprintf("%04d-%02d-%02dT%02d:%02d:%02dZ",
                       year, int(month), day, hour, minute, second)
}

// ---------- Size management (future LRU) ----------
// For now: simple file-count check. Real LRU requires access-time tracking
// in the entry JSON. Handoff §§ PROOF-CACHE §§ size-cap defers full impl.

cache_file_count :: proc(dir: string) -> int {
    if !os.exists(dir) do return 0
    fd, err := os.open(dir)
    if err != nil do return 0
    defer os.close(fd)
    entries, _ := os.read_dir(fd, 0, context.allocator)
    defer delete(entries)
    count := 0
    for e in entries {
        if os.is_dir(e.fullpath) {
            sub_fd, se := os.open(e.fullpath)
            if se != nil do continue
            sub_entries, _ := os.read_dir(sub_fd, 0, context.allocator)
            os.close(sub_fd)
            count += len(sub_entries)
            delete(sub_entries)
        }
    }
    return count
}
