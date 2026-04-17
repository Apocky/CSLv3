package cslparser

// § P2.3 Session-13 : minimal Ed25519 keystore helpers.
// I> scope : load raw 32-byte private/public keys from files.
// I> no protection-at-rest in this version ← dev-stub only ;
//    production keys go through OS-level keyring in Session-14+.
//
// Key files are 32 raw bytes each ; produced by Python's
// cryptography library during the m2_audit.py --init step.
//
// API :
//   keystore_load_private(path)         → ([32]u8, ok)
//   keystore_load_public(path)          → ([32]u8, ok)
//   keystore_save_key(path, key32)      → ok
//   keystore_roundtrip_check()          → bool (used by selftest)

import "core:os"

keystore_load_private :: proc(path: string) -> (key: [32]u8, ok: bool) {
    raw, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil do return {}, false
    defer delete(raw)
    if len(raw) != 32 do return {}, false
    copy(key[:], raw)
    return key, true
}

keystore_load_public :: proc(path: string) -> (key: [32]u8, ok: bool) {
    // Same wire format as private : 32 raw bytes.
    return keystore_load_private(path)
}

keystore_save_key :: proc(path: string, key: []u8) -> bool {
    if len(key) != 32 do return false
    return os.write_entire_file(path, key) == nil
}

// Verifies that sign/verify round-trips cleanly through the keystore path.
// Used by the parser --ed25519-selftest flow.
keystore_roundtrip_check :: proc(priv_path, pub_path, tmp_msg_path: string) -> bool {
    priv, ok1 := keystore_load_private(priv_path)
    if !ok1 do return false
    pub, ok2 := keystore_load_public(pub_path)
    if !ok2 do return false
    msg := "CSLv3 keystore round-trip sentinel"
    sig, sok := ed25519_sign_bytes(transmute([]u8)msg, priv[:])
    if !sok do return false
    return ed25519_verify_bytes(transmute([]u8)msg, sig[:], pub[:])
}
