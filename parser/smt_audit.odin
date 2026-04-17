package cslparser

// § CSLv3 SMT AUDIT-CHAIN (T26.g Session-7)
// I> append-only chain of signed proof-certificates
// I> each entry : {prev_hash, obligation-ctx, result, solver, timestamp, sig}
// I> chain-root : genesis entry signed with dev-stub Ed25519 key
// I> verification : re-hash each entry + verify signature → replay-safe
// I> location : .proof/chain.jsonl   (newline-delimited JSON — append-friendly)
// I> key-location : .proof/keys/     (public.key + private.key — dev-stub)
// R! ← handoff §§ AUDIT-CHAIN + §§ THEORETICAL-NOTES (Alethe/LFSC lightweight-cert)

import "core:crypto/ed25519"
import "core:crypto/hash"
import "core:encoding/base64"
import "core:fmt"
import "core:os"
import "core:strings"

// ---------- Chain entry ----------

Audit_Entry :: struct {
    seq:        int,
    prev_hash:  string,     // SHA256 of previous entry's canonical form ; empty for genesis
    obligation_ctx: string,
    result:     Smt_Result,
    solver:     string,
    cert_hash:  string,     // SHA256 of canonical SMT-LIB2 (same as cache key)
    timestamp:  string,
    signature:  string,     // base64 Ed25519 sig over canonical entry
}

// ---------- Public API ----------

audit_init :: proc(proof_dir: string) -> bool {
    if len(proof_dir) == 0 do return false
    if !os.exists(proof_dir) {
        if os.make_directory(proof_dir) != 0 do return false
    }
    keys_dir := fmt.tprintf("%s/keys", proof_dir)
    if !os.exists(keys_dir) {
        if os.make_directory(keys_dir) != 0 do return false
    }
    priv_path := fmt.tprintf("%s/keys/private.key", proof_dir)
    if !os.exists(priv_path) {
        _ = generate_keypair(proof_dir)
    }
    // genesis entry if chain missing
    chain_path := fmt.tprintf("%s/chain.jsonl", proof_dir)
    if !os.exists(chain_path) {
        _ = write_genesis(proof_dir)
    }
    return true
}

audit_append :: proc(proof_dir: string, ob: ^Obligation) -> bool {
    if !audit_init(proof_dir) do return false

    seq, prev := last_chain_pos(proof_dir)
    e: Audit_Entry
    e.seq = seq + 1
    e.prev_hash = prev
    e.obligation_ctx = strings.clone(ob.context_)
    e.result = ob.result
    e.solver = strings.clone(ob.solver_used)
    e.cert_hash = strings.clone(ob.cert_hash)
    e.timestamp = time_now_iso8601()
    e.signature = sign_entry(proof_dir, &e)

    line := serialize_entry_line(&e)
    defer delete(line)
    chain_path := fmt.tprintf("%s/chain.jsonl", proof_dir)
    // append mode : read existing + append + rewrite (JSONL without stream-append)
    existing, err := os.read_entire_file_from_path(chain_path, context.allocator)
    defer if err == nil do delete(existing, context.allocator)
    buf := strings.builder_make()
    defer strings.builder_destroy(&buf)
    if err == nil do strings.write_string(&buf, string(existing))
    strings.write_string(&buf, line)
    return os.write_entire_file(chain_path, transmute([]byte)strings.to_string(buf)) == nil
}

// Alias so main.odin can shell-out cleanly without exporting smt_audit internals.
ir_verify_audit_chain :: proc(proof_dir: string) -> (bool, int) {
    return audit_verify(proof_dir)
}

audit_verify :: proc(proof_dir: string) -> (ok: bool, checked: int) {
    chain_path := fmt.tprintf("%s/chain.jsonl", proof_dir)
    data, err := os.read_entire_file_from_path(chain_path, context.allocator)
    if err != nil do return false, 0
    defer delete(data, context.allocator)

    pub_key_path := fmt.tprintf("%s/keys/public.key", proof_dir)
    pub_bytes, perr := os.read_entire_file_from_path(pub_key_path, context.allocator)
    if perr != nil do return false, 0
    defer delete(pub_bytes, context.allocator)

    pub: ed25519.Public_Key
    if !ed25519.public_key_set_bytes(&pub, pub_bytes) do return false, 0

    prev := ""
    seq_expected := 0
    n_ok := 0
    rest := string(data)
    for len(rest) > 0 {
        nl := strings.index_byte(rest, '\n')
        line: string
        if nl < 0 { line = rest ; rest = "" }
        else      { line = rest[:nl] ; rest = rest[nl+1:] }
        t := strings.trim_space(line)
        if len(t) == 0 do continue
        e, parsed := parse_entry_line(t)
        if !parsed do return false, n_ok
        if e.prev_hash != prev do return false, n_ok
        if e.seq != seq_expected do return false, n_ok
        // verify signature
        canonical := canonical_entry_bytes(&e)
        sig, berr := base64.decode(e.signature)
        if berr != nil do return false, n_ok
        defer delete(sig)
        if !ed25519.verify(&pub, canonical, sig) do return false, n_ok
        prev = compute_entry_hash(&e)
        seq_expected += 1
        n_ok += 1
    }
    return true, n_ok
}

// ---------- Key management ----------

@(private="file")
generate_keypair :: proc(proof_dir: string) -> bool {
    priv: ed25519.Private_Key
    if !ed25519.private_key_generate(&priv) do return false
    defer ed25519.private_key_clear(&priv)

    priv_bytes: [ed25519.PRIVATE_KEY_SIZE]byte
    ed25519.private_key_bytes(&priv, priv_bytes[:])

    pub: ed25519.Public_Key
    ed25519.public_key_set_priv(&pub, &priv)
    pub_bytes: [ed25519.PUBLIC_KEY_SIZE]byte
    ed25519.public_key_bytes(&pub, pub_bytes[:])

    priv_path := fmt.tprintf("%s/keys/private.key", proof_dir)
    pub_path  := fmt.tprintf("%s/keys/public.key",  proof_dir)
    return os.write_entire_file(priv_path, priv_bytes[:]) == nil &&
           os.write_entire_file(pub_path,  pub_bytes[:])  == nil
}

@(private="file")
load_private_key :: proc(proof_dir: string, out: ^ed25519.Private_Key) -> bool {
    priv_path := fmt.tprintf("%s/keys/private.key", proof_dir)
    bytes, err := os.read_entire_file_from_path(priv_path, context.allocator)
    if err != nil do return false
    defer delete(bytes, context.allocator)
    return ed25519.private_key_set_bytes(out, bytes)
}

// ---------- Signature helpers ----------

@(private="file")
sign_entry :: proc(proof_dir: string, e: ^Audit_Entry) -> string {
    priv: ed25519.Private_Key
    defer ed25519.private_key_clear(&priv)
    if !load_private_key(proof_dir, &priv) do return ""
    canonical := canonical_entry_bytes(e)
    sig: [ed25519.SIGNATURE_SIZE]byte
    ed25519.sign(&priv, canonical, sig[:])
    return base64.encode(sig[:])
}

@(private="file")
canonical_entry_bytes :: proc(e: ^Audit_Entry) -> []byte {
    // Canonical form excludes the signature itself (obviously) + timestamp format-safe.
    s := fmt.tprintf("%d|%s|%s|%s|%s|%s|%s",
                      e.seq, e.prev_hash, e.obligation_ctx,
                      smt_result_name(e.result), e.solver, e.cert_hash, e.timestamp)
    return transmute([]byte)strings.clone(s)
}

@(private="file")
compute_entry_hash :: proc(e: ^Audit_Entry) -> string {
    canonical := canonical_entry_bytes(e)
    defer delete(canonical)
    digest := hash.hash_bytes(.SHA256, canonical)
    defer delete(digest)
    sb := strings.builder_make()
    for b in digest do strings.write_string(&sb, fmt.tprintf("%02x", b))
    return strings.to_string(sb)
}

// ---------- Serialization (JSONL) ----------

@(private="file")
serialize_entry_line :: proc(e: ^Audit_Entry) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, "{")
    strings.write_string(&sb, fmt.tprintf("\"seq\":%d,", e.seq))
    strings.write_string(&sb, fmt.tprintf("\"prev_hash\":%q,", e.prev_hash))
    strings.write_string(&sb, fmt.tprintf("\"ctx\":%q,",        e.obligation_ctx))
    strings.write_string(&sb, fmt.tprintf("\"result\":%q,",     smt_result_name(e.result)))
    strings.write_string(&sb, fmt.tprintf("\"solver\":%q,",     e.solver))
    strings.write_string(&sb, fmt.tprintf("\"cert_hash\":%q,",  e.cert_hash))
    strings.write_string(&sb, fmt.tprintf("\"timestamp\":%q,",  e.timestamp))
    strings.write_string(&sb, fmt.tprintf("\"sig\":%q",         e.signature))
    strings.write_string(&sb, "}\n")
    return strings.to_string(sb)
}

@(private="file")
parse_entry_line :: proc(line: string) -> (Audit_Entry, bool) {
    // Minimal robust-enough JSONL parser for our own emitted lines.
    e: Audit_Entry
    e.seq        = extract_int_field(line, "\"seq\":")
    e.prev_hash  = extract_str_field(line, "\"prev_hash\":")
    e.obligation_ctx = extract_str_field(line, "\"ctx\":")
    e.solver     = extract_str_field(line, "\"solver\":")
    e.cert_hash  = extract_str_field(line, "\"cert_hash\":")
    e.timestamp  = extract_str_field(line, "\"timestamp\":")
    e.signature  = extract_str_field(line, "\"sig\":")
    result_str  := extract_str_field(line, "\"result\":")
    e.result = parse_result_for_audit(result_str)
    return e, true
}

@(private="file")
parse_result_for_audit :: proc(s: string) -> Smt_Result {
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

@(private="file")
extract_str_field :: proc(line, key: string) -> string {
    idx := strings.index(line, key)
    if idx < 0 do return ""
    rest := line[idx + len(key):]
    rest = strings.trim_left_space(rest)
    if len(rest) == 0 || rest[0] != '"' do return ""
    rest = rest[1:]
    // Unescape JSON string literal while advancing to closing quote.
    sb := strings.builder_make()
    i := 0
    for i < len(rest) {
        c := rest[i]
        if c == '"' do break
        if c == '\\' && i + 1 < len(rest) {
            switch rest[i+1] {
            case '"':  strings.write_byte(&sb, '"')
            case '\\': strings.write_byte(&sb, '\\')
            case 'n':  strings.write_byte(&sb, '\n')
            case 'r':  strings.write_byte(&sb, '\r')
            case 't':  strings.write_byte(&sb, '\t')
            case '/':  strings.write_byte(&sb, '/')
            case:      strings.write_byte(&sb, rest[i+1])
            }
            i += 2
            continue
        }
        strings.write_byte(&sb, c)
        i += 1
    }
    return strings.to_string(sb)
}

@(private="file")
extract_int_field :: proc(line, key: string) -> int {
    idx := strings.index(line, key)
    if idx < 0 do return 0
    rest := line[idx + len(key):]
    rest = strings.trim_left_space(rest)
    n := 0
    sign := 1
    i := 0
    if i < len(rest) && rest[i] == '-' { sign = -1 ; i += 1 }
    for i < len(rest) && rest[i] >= '0' && rest[i] <= '9' {
        n = n * 10 + int(rest[i] - '0')
        i += 1
    }
    return sign * n
}

// ---------- Genesis ----------

@(private="file")
write_genesis :: proc(proof_dir: string) -> bool {
    e: Audit_Entry
    e.seq = 0
    e.prev_hash = ""
    e.obligation_ctx = "GENESIS"
    e.result = .Pending
    e.solver = "none"
    e.cert_hash = strings.repeat("0", 64)
    e.timestamp = time_now_iso8601()
    e.signature = sign_entry(proof_dir, &e)
    line := serialize_entry_line(&e)
    defer delete(line)
    chain_path := fmt.tprintf("%s/chain.jsonl", proof_dir)
    return os.write_entire_file(chain_path, transmute([]byte)line) == nil
}

@(private="file")
last_chain_pos :: proc(proof_dir: string) -> (seq: int, prev_hash: string) {
    chain_path := fmt.tprintf("%s/chain.jsonl", proof_dir)
    data, err := os.read_entire_file_from_path(chain_path, context.allocator)
    if err != nil do return -1, ""
    defer delete(data, context.allocator)

    last_line := ""
    rest := string(data)
    for len(rest) > 0 {
        nl := strings.index_byte(rest, '\n')
        line: string
        if nl < 0 { line = rest ; rest = "" }
        else      { line = rest[:nl] ; rest = rest[nl+1:] }
        t := strings.trim_space(line)
        if len(t) > 0 do last_line = t
    }
    if len(last_line) == 0 do return -1, ""
    e, ok := parse_entry_line(last_line)
    if !ok do return -1, ""
    return e.seq, compute_entry_hash(&e)
}
