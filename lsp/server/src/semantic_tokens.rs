// § CSLv3 LSP — semantic-tokens provider (T24 Session-9)
// I> 74-glyph highlighting beyond-TextMate ; per-character tokenization
// I> token-types matched to LSP SemanticTokenType :
//    keyword (modals W! N! R! M? I> Q?) + operator (. + - @ ⊗) +
//    type (i32 f32 bool etc.) + variable (idents) + comment + string

use tower_lsp::lsp_types::{SemanticToken, SemanticTokens};

pub const TOKEN_TYPES: &[&str] = &[
    "keyword",
    "operator",
    "comment",
    "string",
    "number",
    "variable",
    "type",
    "macro",
    "regexp",
];

// token-type indices into TOKEN_TYPES
const T_KEYWORD: u32 = 0;
const T_OPERATOR: u32 = 1;
const T_COMMENT: u32 = 2;
const T_STRING: u32 = 3;
const T_NUMBER: u32 = 4;
#[allow(dead_code)]
const T_VARIABLE: u32 = 5;
#[allow(dead_code)]
const T_TYPE: u32 = 6;
const T_MACRO: u32 = 7;

pub fn tokens_for(text: &str) -> SemanticTokens {
    let mut out: Vec<SemanticToken> = Vec::new();
    let mut prev_line: u32 = 0;
    let mut prev_col: u32 = 0;

    for (line_idx, line) in text.lines().enumerate() {
        let line_u = line_idx as u32;
        // Comment line : whole-line token
        let trimmed = line.trim_start();
        if trimmed.starts_with('#') {
            let lead_cols = (line.len() - trimmed.len()) as u32;
            let token_len = line.chars().count() as u32 - lead_cols;
            push(&mut out, &mut prev_line, &mut prev_col, line_u, lead_cols, token_len, T_COMMENT);
            continue;
        }
        let mut col: u32 = 0;
        let chars: Vec<char> = line.chars().collect();
        let mut i = 0;
        while i < chars.len() {
            let c = chars[i];
            // String literal
            if c == '"' {
                let start = col;
                let mut end = i + 1;
                while end < chars.len() && chars[end] != '"' {
                    end += 1;
                }
                if end < chars.len() {
                    end += 1;
                }
                let len = (end - i) as u32;
                push(&mut out, &mut prev_line, &mut prev_col, line_u, start, len, T_STRING);
                col += len;
                i = end;
                continue;
            }
            // Number
            if c.is_ascii_digit() {
                let start = col;
                let mut end = i;
                while end < chars.len() && (chars[end].is_ascii_digit() || chars[end] == '.') {
                    end += 1;
                }
                let len = (end - i) as u32;
                push(&mut out, &mut prev_line, &mut prev_col, line_u, start, len, T_NUMBER);
                col += len;
                i = end;
                continue;
            }
            // Modal tokens : two-char suffix "! ?"
            if (c == 'I' || c == 'W' || c == 'R' || c == 'M' || c == 'N' || c == 'Q')
                && i + 1 < chars.len()
                && (chars[i + 1] == '!' || chars[i + 1] == '?' || chars[i + 1] == '>')
            {
                push(&mut out, &mut prev_line, &mut prev_col, line_u, col, 2, T_MACRO);
                col += 2;
                i += 2;
                continue;
            }
            // Section glyph / star-operator keyword characters
            if matches!(
                c,
                '§' | '¶' | '→' | '←' | '↔' | '≤' | '≥' | '≠' |
                '∧' | '∨' | '¬' | '∀' | '∃' | '∈' | '⊆' | '⊂' |
                '∪' | '∩' | '⇒' | '∵' | '∴' | '⊗' | '⊕' | '⟨' |
                '⟩' | '⌈' | '⌉' | '⟦' | '⟧' | '«' | '»' | '⟪' | '⟫' |
                '∫' | '⊞' | '⊑' | '⊔' | '⊓' | 'λ' | 'π' | 'μ' | 'ν'
            ) {
                push(&mut out, &mut prev_line, &mut prev_col, line_u, col, 1, T_KEYWORD);
                col += 1;
                i += 1;
                continue;
            }
            // Evidence markers single-char
            if matches!(c, '✓' | '✗' | '◐' | '○' | '⊘' | '△' | '▽' | '‼') {
                push(&mut out, &mut prev_line, &mut prev_col, line_u, col, 1, T_MACRO);
                col += 1;
                i += 1;
                continue;
            }
            // Compound operators
            if matches!(c, '.' | '+' | '-' | '@' | ':' | '=' | '|' | '&' | '^') {
                push(&mut out, &mut prev_line, &mut prev_col, line_u, col, 1, T_OPERATOR);
                col += 1;
                i += 1;
                continue;
            }
            // advance
            col += 1;
            i += 1;
        }
    }

    SemanticTokens {
        result_id: None,
        data: out,
    }
}

fn push(
    out: &mut Vec<SemanticToken>,
    prev_line: &mut u32,
    prev_col: &mut u32,
    line: u32,
    col: u32,
    length: u32,
    type_: u32,
) {
    let delta_line = line - *prev_line;
    let delta_start = if delta_line == 0 {
        col - *prev_col
    } else {
        col
    };
    out.push(SemanticToken {
        delta_line,
        delta_start,
        length,
        token_type: type_,
        token_modifiers_bitset: 0,
    });
    *prev_line = line;
    *prev_col = col;
}
