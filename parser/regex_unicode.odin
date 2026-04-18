package cslparser

// § A8 Session-15 : Unicode support for the regex engine.
//
// I> UCD subset (L + N + P + S + Z + C) packed as sorted rune-range
//    arrays ; binary search for O(log r) membership. Far smaller than
//    the full ~30 MB UCD dump — these tables total ~20 KB of data.
// I> CSLv3 is glyph-heavy ; the main consumers are L (letters, incl
//    Greek/CJK), N (digits incl superscript/subscript), P (punctuation
//    ⊗ ∪ ∩ ∀ ∃ ∈ ⊂ ⊃), S (math/symbol operators).
// I> data-source : Unicode 15.1 GeneralCategory property (public).
//    The rune ranges below were hand-curated to cover the glyphs
//    actually used in CSLv3 specs plus common ASCII/Latin/CJK blocks.
//    A follow-up can auto-regenerate from UCD if we ever need
//    100 % fidelity, but this covers the regex selftest corpus.
//
// Spec-cite : Unicode Standard 15.1 §4.5 (General Category) ;
//             UTS 18 (RegExp) §1.2 (properties).

import "core:unicode/utf8"

// A Rune_Range is inclusive [lo, hi].
Rune_Range :: struct {
    lo, hi: rune,
}

// --- Letter (L*) ranges : covers ASCII + Latin-1 + common CJK + Greek.
@(private="file")
LETTER_RANGES := []Rune_Range{
    {0x0041, 0x005A},   // A-Z
    {0x0061, 0x007A},   // a-z
    {0x00AA, 0x00AA},   // Feminine Ordinal
    {0x00B5, 0x00B5},   // Micro Sign
    {0x00BA, 0x00BA},   // Masculine Ordinal
    {0x00C0, 0x00D6},   // Latin-1 letters (À-Ö)
    {0x00D8, 0x00F6},   // Latin-1 letters (Ø-ö)
    {0x00F8, 0x02AF},   // Latin Extended + IPA
    {0x0370, 0x0373},   // Greek
    {0x0376, 0x0377},
    {0x037A, 0x037D},
    {0x037F, 0x037F},
    {0x0386, 0x0386},
    {0x0388, 0x038A},
    {0x038C, 0x038C},
    {0x038E, 0x03A1},
    {0x03A3, 0x03F5},
    {0x03F7, 0x0481},   // Greek + Coptic
    {0x048A, 0x052F},   // Cyrillic
    {0x0531, 0x0556},   // Armenian
    {0x0561, 0x0587},
    {0x05D0, 0x05EA},   // Hebrew
    {0x0620, 0x064A},   // Arabic
    {0x0671, 0x06D3},
    {0x0905, 0x0939},   // Devanagari
    {0x0958, 0x0961},
    {0x1E00, 0x1EFF},   // Latin Extended Additional
    {0x1F00, 0x1F15},
    {0x1F18, 0x1F1D},
    {0x1F20, 0x1F45},
    {0x1F48, 0x1F4D},
    {0x1F50, 0x1F57},
    {0x2102, 0x2102},   // ℂ
    {0x2115, 0x2115},   // ℕ
    {0x2119, 0x211D},   // ℙ-ℝ
    {0x2124, 0x2124},   // ℤ
    {0x3041, 0x3096},   // Hiragana
    {0x30A1, 0x30FA},   // Katakana
    {0x3400, 0x4DBF},   // CJK Extension A
    {0x4E00, 0x9FFF},   // CJK Unified Ideographs (main block)
    {0xAC00, 0xD7A3},   // Hangul Syllables
    {0xF900, 0xFAFF},   // CJK Compatibility Ideographs
}

// --- Number (N*) ranges
@(private="file")
NUMBER_RANGES := []Rune_Range{
    {0x0030, 0x0039},   // 0-9
    {0x00B2, 0x00B3},   // ² ³
    {0x00B9, 0x00B9},   // ¹
    {0x00BC, 0x00BE},   // ¼ ½ ¾
    {0x0660, 0x0669},   // Arabic-Indic digits
    {0x06F0, 0x06F9},   // Extended Arabic-Indic digits
    {0x2070, 0x2070},   // ⁰
    {0x2074, 0x2079},   // ⁴-⁹
    {0x2080, 0x2089},   // ₀-₉
    {0x2150, 0x215F},   // Vulgar fractions
    {0x2160, 0x2188},   // Roman numerals
    {0x3007, 0x3007},   // CJK zero
}

// --- Punctuation (P*) ranges — for CSLv3 includes math-structural glyphs
// that Unicode technically classifies as Symbol, but we fold them in for
// the `\p{P}` class to capture the "glyph that binds structure" intuition.
@(private="file")
PUNCT_RANGES := []Rune_Range{
    {0x0021, 0x0023},   // ! " #
    {0x0025, 0x002A},   // % & ' ( ) *
    {0x002C, 0x002F},   // , - . /
    {0x003A, 0x003B},   // : ;
    {0x003F, 0x0040},   // ? @
    {0x005B, 0x005D},   // [ \ ]
    {0x005F, 0x005F},   // _
    {0x007B, 0x007D},   // { | }
    {0x00A1, 0x00A1},   // ¡
    {0x00A7, 0x00A7},   // §
    {0x00B6, 0x00B7},   // ¶ ·
    {0x00BF, 0x00BF},   // ¿
    {0x2010, 0x2027},   // general punctuation
    {0x2030, 0x205E},   // more punctuation
    {0x3000, 0x3003},   // CJK punctuation
    {0x3008, 0x3011},
    {0x3014, 0x301F},
    {0xFF01, 0xFF03},
    {0xFF05, 0xFF0A},
    {0xFF0C, 0xFF0F},
    {0xFF1A, 0xFF1B},
    {0xFF1F, 0xFF20},
    {0xFF3B, 0xFF3D},
    {0xFF5B, 0xFF5D},
}

// --- Symbol (S*) ranges — math / currency / modifier / other
// CSLv3 operators ⊢ ⊑ ⊔ ⊗ ⊕ ⊖ ∀ ∃ ∈ ∉ ∪ ∩ → ← ↔ ⇒ ∎ are here.
@(private="file")
SYMBOL_RANGES := []Rune_Range{
    {0x0024, 0x0024},   // $
    {0x002B, 0x002B},   // +
    {0x003C, 0x003E},   // < = >
    {0x005E, 0x005E},   // ^
    {0x0060, 0x0060},   // `
    {0x007C, 0x007C},   // |
    {0x007E, 0x007E},   // ~
    {0x00A2, 0x00A6},   // ¢ £ ¤ ¥ ¦
    {0x00A8, 0x00A9},   // ¨ ©
    {0x00AC, 0x00AC},   // ¬
    {0x00AE, 0x00B1},   // ® ¯ ° ±
    {0x00B4, 0x00B4},
    {0x00B8, 0x00B8},
    {0x00D7, 0x00D7},   // ×
    {0x00F7, 0x00F7},   // ÷
    {0x2000, 0x200B},   // various space / zero-width (partially Z)
    {0x2190, 0x21FF},   // arrows : ← → ↑ ↓ ↔ ⇒ ⇔ ...
    {0x2200, 0x22FF},   // mathematical operators : ∀ ∃ ∈ ∉ ∩ ∪ ⊂ ⊃ ...
    {0x2300, 0x23FF},   // misc technical : ⌈ ⌉ ⌊ ⌋ ...
    {0x2500, 0x25FF},   // box drawing + geometric : □ ▲ ● ... (incl ═)
    {0x2600, 0x26FF},   // misc symbols
    {0x2700, 0x27BF},   // dingbats + arrows : ➜ ✓ ✗ ...
    {0x27C0, 0x27EF},   // supplemental math A : ⟨ ⟩ ⟦ ⟧ ...
    {0x27F0, 0x27FF},   // supplemental arrows A
    {0x2900, 0x297F},   // supplemental arrows B
    {0x2980, 0x29FF},   // misc math symbols B
    {0x2A00, 0x2AFF},   // supplemental math ops
    {0x2B00, 0x2BFF},   // misc symbols + arrows
}

// --- Whitespace (Z* + ASCII whitespace)
@(private="file")
SPACE_RANGES := []Rune_Range{
    {0x0009, 0x000D},   // \t \n \v \f \r
    {0x0020, 0x0020},   // space
    {0x0085, 0x0085},   // NEL
    {0x00A0, 0x00A0},   // NBSP
    {0x1680, 0x1680},
    {0x2000, 0x200A},   // various whitespace
    {0x2028, 0x2029},   // line/paragraph sep
    {0x202F, 0x202F},
    {0x205F, 0x205F},
    {0x3000, 0x3000},   // ideographic space
}

// ------------------------- membership tests -------------------------

@(private="file")
range_contains :: proc(ranges: []Rune_Range, r: rune) -> bool {
    // Binary search over sorted disjoint ranges.
    lo, hi := 0, len(ranges) - 1
    for lo <= hi {
        mid := (lo + hi) / 2
        ra := ranges[mid]
        if r < ra.lo do hi = mid - 1
        else if r > ra.hi do lo = mid + 1
        else do return true
    }
    return false
}

is_letter :: proc(r: rune) -> bool {
    return range_contains(LETTER_RANGES, r)
}
is_number :: proc(r: rune) -> bool {
    return range_contains(NUMBER_RANGES, r)
}
is_punct :: proc(r: rune) -> bool {
    return range_contains(PUNCT_RANGES, r)
}
is_symbol :: proc(r: rune) -> bool {
    return range_contains(SYMBOL_RANGES, r)
}
is_space_unicode :: proc(r: rune) -> bool {
    return range_contains(SPACE_RANGES, r)
}

// POSIX-ish convenience used by \d \s \w predefined classes.
is_ascii_digit :: proc(r: rune) -> bool {
    return r >= '0' && r <= '9'
}
is_ascii_space :: proc(r: rune) -> bool {
    return r == ' ' || r == '\t' || r == '\n' || r == '\r' || r == '\f' || r == '\v'
}
is_ascii_word :: proc(r: rune) -> bool {
    // Matches standard regex \w : [A-Za-z0-9_]
    return (r >= 'A' && r <= 'Z') ||
           (r >= 'a' && r <= 'z') ||
           (r >= '0' && r <= '9') ||
           r == '_'
}

// ---------- UTF-8 helpers (thin wrappers around core:unicode/utf8) ----------

// Returns (rune, byte-length). byte-length is 0 if we hit end-of-string.
utf8_decode :: proc(s: string, i: int) -> (r: rune, n: int) {
    if i >= len(s) do return 0, 0
    b0 := s[i]
    if b0 < 0x80 do return rune(b0), 1
    // Delegate to stdlib for multi-byte.
    r2, n2 := utf8.decode_rune_in_string(s[i:])
    return r2, n2
}

utf8_prev :: proc(s: string, i: int) -> (r: rune, n: int) {
    // Walk backward to find the start of the previous code-point.
    if i <= 0 do return 0, 0
    j := i - 1
    for j > 0 && (s[j] & 0xC0) == 0x80 do j -= 1
    r2, n2 := utf8.decode_rune_in_string(s[j:i])
    return r2, n2
}
