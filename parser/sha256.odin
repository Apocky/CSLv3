package cslparser

// § P2.2 Session-13 : SHA-256 bespoke implementation (FIPS 180-4).
// I> replaces : OS sha256sum / Python hashlib for manifest generation
// I> ~200 LOC • 64-round compression • big-endian output
// I> verified against NIST FIPS-180-4 published test vectors
//
// API :
//   sha256(data : []u8)            -> [32]u8
//   sha256_hex(data : []u8)        -> string    (lowercase hex)
//   sha256_file(path : string)     -> (ok, hex)
//   sha256_selftest()              -> prints NIST-vector verdicts
//
// Spec-cite : FIPS 180-4 §6.2 (SHA-256 definition).

import "core:fmt"
import "core:os"

// Initial hash values H(0) — first 32 bits of fractional parts of
// square roots of the first 8 primes. FIPS 180-4 §5.3.3.
@(private="file")
H0_256 := [8]u32{
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
}

// Round constants K — first 32 bits of fractional parts of cube
// roots of the first 64 primes. FIPS 180-4 §4.2.2.
@(private="file")
K_256 := [64]u32{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

// 32-bit rotate-right. FIPS 180-4 §3.2.
@(private="file")
rotr32 :: #force_inline proc "contextless" (x: u32, n: u32) -> u32 {
    return (x >> n) | (x << (32 - n))
}

// Mutable SHA-256 state. Block-at-a-time API so `update` can stream.
Sha256_Ctx :: struct {
    h:        [8]u32,     // running hash
    buf:      [64]u8,     // unprocessed bytes (< 1 block)
    buf_len:  int,
    total:    u64,        // total bytes consumed (for length pad)
}

sha256_init :: proc(ctx: ^Sha256_Ctx) {
    ctx.h = H0_256
    ctx.buf_len = 0
    ctx.total = 0
}

sha256_update :: proc(ctx: ^Sha256_Ctx, data: []u8) {
    ctx.total += u64(len(data))
    i := 0
    // If we have a partial buffer, fill it first.
    if ctx.buf_len > 0 {
        want := 64 - ctx.buf_len
        if len(data) < want {
            copy(ctx.buf[ctx.buf_len:], data)
            ctx.buf_len += len(data)
            return
        }
        copy(ctx.buf[ctx.buf_len:], data[:want])
        sha256_compress(ctx, ctx.buf[:])
        ctx.buf_len = 0
        i = want
    }
    // Full blocks directly from `data`.
    for i + 64 <= len(data) {
        sha256_compress(ctx, data[i:i+64])
        i += 64
    }
    // Trailing partial block → buffer.
    if i < len(data) {
        copy(ctx.buf[:], data[i:])
        ctx.buf_len = len(data) - i
    }
}

sha256_final :: proc(ctx: ^Sha256_Ctx) -> [32]u8 {
    // MD-strengthening pad : append 0x80, then zeros, then 64-bit length BE.
    bit_len := ctx.total * 8
    pad_start := ctx.buf_len
    ctx.buf[pad_start] = 0x80
    // if < 56 bytes of pad-room, compress and start fresh.
    if pad_start + 1 > 56 {
        for i in (pad_start + 1) ..< 64 do ctx.buf[i] = 0
        sha256_compress(ctx, ctx.buf[:])
        for i in 0 ..< 56 do ctx.buf[i] = 0
    } else {
        for i in (pad_start + 1) ..< 56 do ctx.buf[i] = 0
    }
    // 64-bit BE length in last 8 bytes.
    ctx.buf[56] = u8(bit_len >> 56)
    ctx.buf[57] = u8(bit_len >> 48)
    ctx.buf[58] = u8(bit_len >> 40)
    ctx.buf[59] = u8(bit_len >> 32)
    ctx.buf[60] = u8(bit_len >> 24)
    ctx.buf[61] = u8(bit_len >> 16)
    ctx.buf[62] = u8(bit_len >> 8)
    ctx.buf[63] = u8(bit_len)
    sha256_compress(ctx, ctx.buf[:])

    // Serialize h[] big-endian.
    out: [32]u8
    for i in 0 ..< 8 {
        out[4*i + 0] = u8(ctx.h[i] >> 24)
        out[4*i + 1] = u8(ctx.h[i] >> 16)
        out[4*i + 2] = u8(ctx.h[i] >> 8)
        out[4*i + 3] = u8(ctx.h[i])
    }
    return out
}

@(private="file")
sha256_compress :: proc(ctx: ^Sha256_Ctx, block: []u8) {
    // Message schedule W[0..64]. FIPS 180-4 §6.2.2 step 1.
    W: [64]u32
    for t in 0 ..< 16 {
        W[t] = (u32(block[4*t + 0]) << 24) |
               (u32(block[4*t + 1]) << 16) |
               (u32(block[4*t + 2]) << 8)  |
                u32(block[4*t + 3])
    }
    for t in 16 ..< 64 {
        s0 := rotr32(W[t-15], 7) ~ rotr32(W[t-15], 18) ~ (W[t-15] >> 3)
        s1 := rotr32(W[t-2], 17) ~ rotr32(W[t-2], 19)  ~ (W[t-2]  >> 10)
        W[t] = W[t-16] + s0 + W[t-7] + s1
    }

    // Working vars. FIPS 180-4 §6.2.2 step 2.
    a := ctx.h[0]; b := ctx.h[1]; c := ctx.h[2]; d := ctx.h[3]
    e := ctx.h[4]; f := ctx.h[5]; g := ctx.h[6]; h := ctx.h[7]

    // 64 rounds.
    for t in 0 ..< 64 {
        S1 := rotr32(e, 6) ~ rotr32(e, 11) ~ rotr32(e, 25)
        ch := (e & f) ~ ((~e) & g)
        T1 := h + S1 + ch + K_256[t] + W[t]
        S0 := rotr32(a, 2) ~ rotr32(a, 13) ~ rotr32(a, 22)
        mj := (a & b) ~ (a & c) ~ (b & c)
        T2 := S0 + mj
        h = g; g = f; f = e; e = d + T1
        d = c; c = b; b = a; a = T1 + T2
    }

    // Update hash. FIPS 180-4 §6.2.2 step 4.
    ctx.h[0] += a; ctx.h[1] += b; ctx.h[2] += c; ctx.h[3] += d
    ctx.h[4] += e; ctx.h[5] += f; ctx.h[6] += g; ctx.h[7] += h
}

// Convenience : one-shot.
sha256 :: proc(data: []u8) -> [32]u8 {
    ctx: Sha256_Ctx
    sha256_init(&ctx)
    sha256_update(&ctx, data)
    return sha256_final(&ctx)
}

sha256_hex :: proc(data: []u8, allocator := context.allocator) -> string {
    h := sha256(data)
    return bytes_to_hex(h[:], allocator)
}

sha256_file :: proc(path: string) -> (ok: bool, hex: string) {
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != nil do return false, ""
    defer delete(data)
    return true, sha256_hex(data)
}

// Generic hex helper — shared with SHA-512 / Ed25519 output formatting.
bytes_to_hex :: proc(b: []u8, allocator := context.allocator) -> string {
    context.allocator = allocator
    HEX := "0123456789abcdef"
    out := make([]u8, 2 * len(b))
    for v, i in b {
        out[2*i]     = HEX[v >> 4]
        out[2*i + 1] = HEX[v & 0xf]
    }
    return string(out)
}

// NIST FIPS-180-4 published test vectors.
//   empty                      e3b0c442 98fc1c14 9afbf4c8 996fb924 27ae41e4 649b934c a495991b 7852b855
//   "abc"                      ba7816bf 8f01cfea 414140de 5dae2223 b00361a3 96177a9c b410ff61 f20015ad
//   "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
//                              248d6a61 d20638b8 e5c02693 0c3e6039 a33ce459 64ff2167 f6ecedd4 19db06c1
sha256_selftest :: proc() {
    print :: fmt.printf
    type_vec :: struct { name, input, want: string }
    vectors := []type_vec{
        { "empty",       "", "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" },
        { "abc",         "abc", "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" },
        { "multi-block",
          "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1" },
        // 1,000,000 × 'a' — FIPS longer test-vector proves streaming correctness.
        // We encode the input by repeating at runtime rather than inlining the
        // megabyte literal.
        { "million-a", "", "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0" },
    }
    fail := 0
    // Pre-build the million-a buffer ONCE outside the loop so its lifetime
    // outlives the iteration that uses it. Using context.temp_allocator so
    // cleanup happens on selftest exit.
    million_a := make([]u8, 1_000_000, context.temp_allocator)
    for i in 0 ..< 1_000_000 do million_a[i] = 'a'

    for v, _ in vectors {
        input_bytes: []u8
        if v.name == "million-a" {
            input_bytes = million_a
        } else {
            input_bytes = transmute([]u8)v.input
        }
        got := sha256_hex(input_bytes, context.temp_allocator)
        mark := "OK"
        if got != v.want {
            mark = "FAIL"
            fail += 1
        }
        print("%-12s %s\n", v.name, mark)
        if got != v.want {
            print("  got : %s\n  want: %s\n", got, v.want)
        }
    }
    if fail == 0 {
        print("§ SHA-256 selftest : 4/4 NIST vectors verified\n")
        os.exit(0)
    } else {
        print("§ SHA-256 selftest : %d failures\n", fail)
        os.exit(1)
    }
}
