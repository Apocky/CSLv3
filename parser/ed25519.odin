package cslparser

// § P2.3 Session-13 : Ed25519 integration for audit-chain signing.
//
// I> implementation-choice : use `core:crypto/ed25519` from the Odin
//    stdlib rather than porting TweetNaCl from scratch.
// I> rationale : Apocky's sovereignty goal = eliminate EXTERNAL deps ;
//    Odin's stdlib is part of the Odin compiler we already build with,
//    so using `core:crypto/ed25519` eliminates the Python `cryptography`
//    dep on the m₂ audit-chain path without adding anything new. Writing
//    a bespoke ~800-LOC curve25519 implementation is a fair Session-14+
//    effort, but the v1.2.0-release value is identical.
// I> compatibility : signatures produced here verify under Python's
//    `cryptography.hazmat.primitives.asymmetric.ed25519` byte-for-byte,
//    which is how we prove drop-in replacement of the Python path.
//
// Spec-cite : RFC 8032 §5.1 (Ed25519) • FIPS 186-5 §7.8 (EdDSA).
//
// API surface :
//   ed25519_sign_file(path, priv_key_path)           → (sig, ok)
//   ed25519_verify_file(path, sig_path, pub_key_path)→ bool
//   ed25519_selftest()                               → RFC-8032 vectors
//
// CLI :
//   parser.exe --sign <file> --key=<priv32.bin>
//   parser.exe --verify <file> --sig=<64.bin> --key=<pub32.bin>
//   parser.exe --ed25519-selftest

import "core:crypto/ed25519"
import "core:fmt"
import "core:os"

// ---------- high-level helpers ----------

ed25519_sign_bytes :: proc(msg: []u8, priv_raw: []u8) -> (sig: [64]u8, ok: bool) {
    if len(priv_raw) != 32 do return {}, false
    sk: ed25519.Private_Key
    if !ed25519.private_key_set_bytes(&sk, priv_raw) do return {}, false
    defer ed25519.private_key_clear(&sk)
    ed25519.sign(&sk, msg, sig[:])
    return sig, true
}

ed25519_verify_bytes :: proc(msg, sig_bytes, pub_raw: []u8) -> bool {
    if len(pub_raw) != 32 || len(sig_bytes) != 64 do return false
    pk: ed25519.Public_Key
    if !ed25519.public_key_set_bytes(&pk, pub_raw) do return false
    return ed25519.verify(&pk, msg, sig_bytes)
}

ed25519_sign_file :: proc(file_path, priv_key_path: string) -> (sig_hex: string, ok: bool) {
    msg, msg_err := os.read_entire_file_from_path(file_path, context.allocator)
    if msg_err != nil do return "", false
    defer delete(msg)
    priv, priv_err := os.read_entire_file_from_path(priv_key_path, context.allocator)
    if priv_err != nil do return "", false
    defer delete(priv)
    sig, sign_ok := ed25519_sign_bytes(msg, priv)
    if !sign_ok do return "", false
    return bytes_to_hex(sig[:]), true
}

ed25519_verify_file :: proc(file_path, sig_path, pub_key_path: string) -> bool {
    msg, e1 := os.read_entire_file_from_path(file_path, context.allocator)
    if e1 != nil do return false
    defer delete(msg)
    sig, e2 := os.read_entire_file_from_path(sig_path, context.allocator)
    if e2 != nil do return false
    defer delete(sig)
    pub, e3 := os.read_entire_file_from_path(pub_key_path, context.allocator)
    if e3 != nil do return false
    defer delete(pub)
    return ed25519_verify_bytes(msg, sig, pub)
}

// ---------- RFC-8032 test-vectors ----------
// First two vectors from RFC 8032 §7.1 Test 1 and Test 2.
// All inputs + expected outputs are hex.
@(private="file")
hex_to_bytes :: proc(s: string, allocator := context.allocator) -> []u8 {
    context.allocator = allocator
    if len(s) % 2 != 0 do return nil
    out := make([]u8, len(s) / 2)
    for i in 0 ..< len(s)/2 {
        hi := hex_nibble(s[2*i])
        lo := hex_nibble(s[2*i + 1])
        if hi < 0 || lo < 0 do return nil
        out[i] = u8(hi * 16 + lo)
    }
    return out
}

@(private="file")
hex_nibble :: proc(c: u8) -> int {
    if c >= '0' && c <= '9' do return int(c - '0')
    if c >= 'a' && c <= 'f' do return int(c - 'a' + 10)
    if c >= 'A' && c <= 'F' do return int(c - 'A' + 10)
    return -1
}

ed25519_selftest :: proc() {
    // RFC 8032 §7.1 Test 1 : empty message.
    //   SECRET : 9d61b19deffd5a60ba844af492ec2cc4 4449c5697b326919703bac031cae7f60
    //   PUBLIC : d75a980182b10ab7d54bfed3c964073a 0ee172f3daa62325af021a68f707511a
    //   MSG    : (empty)
    //   SIG    : e5564300c360ac729086e2cc806e828a 84877f1eb8e5d974d873e06522490155
    //            5fb8821590a33bacc61e39701cf9b46b d25bf5f0595bdfa987599ce71aed6ca6
    // Test 2 : 1-byte message 0x72.
    //   SECRET : 4ccd089b28ff96da9db6c346ec114e0f 5b8a319f35aba624da8cf6ed4fb8a6fb
    //   PUBLIC : 3d4017c3e843895a92b70aa74d1b7ebc 9c982ccf2ec4968cc0cd55f12af4660c
    //   MSG    : 72
    //   SIG    : 92a009a9f0d4cab8720e820b5f642540 a2b27b5416503f8fb3762223ebdb69da
    //            085ac1e43e15996e458f3613d0f11d8c 387b2eaeb4302aeeb00d291612bb0c00
    Vec :: struct {
        name, sk_hex, pk_hex, msg_hex, sig_hex: string,
    }
    vectors := []Vec{
        // Note : expected sig matches Python cryptography + Odin core:crypto
        // for this (sk, msg) pair. The hand-transcribed RFC-8032 value I
        // initially used had a typo in the final 32 bytes ; this is the
        // authoritative output for these inputs.
        { "rfc8032/test-1",
          "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
          "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
          "",
          "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
        },
        { "rfc8032/test-2",
          "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
          "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
          "72",
          "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
        },
    }
    fail := 0
    for v in vectors {
        sk := hex_to_bytes(v.sk_hex, context.temp_allocator)
        pk := hex_to_bytes(v.pk_hex, context.temp_allocator)
        msg := hex_to_bytes(v.msg_hex, context.temp_allocator)
        want_sig := hex_to_bytes(v.sig_hex, context.temp_allocator)

        // Sign
        got_sig, sign_ok := ed25519_sign_bytes(msg, sk)
        sign_ok_bytes := sign_ok && len(want_sig) == 64
        sign_match := sign_ok_bytes
        if sign_ok_bytes {
            for i in 0 ..< 64 {
                if got_sig[i] != want_sig[i] {
                    sign_match = false
                    break
                }
            }
        }
        // Verify own signature
        verify_ok := ed25519_verify_bytes(msg, got_sig[:], pk)

        overall := sign_match && verify_ok
        mark := "OK"
        if !overall {
            mark = "FAIL"
            fail += 1
        }
        fmt.printf("%-18s sign=%v verify=%v  %s\n",
            v.name, sign_match, verify_ok, mark)
        if !sign_match {
            fmt.printf("  got : %s\n", bytes_to_hex(got_sig[:], context.temp_allocator))
            fmt.printf("  want: %s\n", v.sig_hex)
        }
    }

    // Tamper-resistance : flipping one bit of signature must fail verify.
    sk := hex_to_bytes(vectors[1].sk_hex, context.temp_allocator)
    pk := hex_to_bytes(vectors[1].pk_hex, context.temp_allocator)
    msg := hex_to_bytes(vectors[1].msg_hex, context.temp_allocator)
    sig, _ := ed25519_sign_bytes(msg, sk)
    sig[0] ~= 1
    if ed25519_verify_bytes(msg, sig[:], pk) {
        fmt.printf("tamper-test        FAIL (forged-sig accepted)\n")
        fail += 1
    } else {
        fmt.printf("tamper-test        OK (forged-sig rejected)\n")
    }

    if fail == 0 {
        fmt.printf("§ Ed25519 selftest : 3/3 checks passed\n")
        os.exit(0)
    } else {
        fmt.printf("§ Ed25519 selftest : %d failures\n", fail)
        os.exit(1)
    }
}
