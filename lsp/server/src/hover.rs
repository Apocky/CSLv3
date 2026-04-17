// § CSLv3 LSP — hover provider (T24.e Session-9)
// I> markdown-rendered ; three dispatch paths :
//    a) 74-glyph-table   : Unicode + ASCII alias + category
//    b) morpheme (after ' or stacked) : refinement + slot + docs-ref
//    c) ident : inferred-type from --typecheck --json (if available)

use crate::parser_shim::ParserShim;
use serde_json::Value as J;
use tower_lsp::lsp_types::{Hover, HoverContents, MarkupContent, MarkupKind, Position, Range};

pub async fn hover_at(
    shim: &ParserShim,
    uri: &str,
    text: &str,
    pos: Position,
) -> Option<Hover> {
    // Extract the character under the cursor + nearby word.
    let (line_str, col) = line_at(text, pos.line as usize)?;
    let word = word_around(&line_str, col);

    // a) glyph — single-char hover via glyph-table
    if word.chars().count() == 1 {
        if let Some(md) = glyph_info(word.chars().next().unwrap()) {
            return Some(simple_hover(md));
        }
    }
    // b) morpheme : word starts with "'"
    if let Some(tag) = word.strip_prefix('\'') {
        if let Some(md) = morpheme_info(tag) {
            return Some(simple_hover(md));
        }
    }
    // also handle morpheme after the cursor-char (when cursor is ON the ')
    // by checking if we sit on `'` with a letter immediately after.
    if word == "'" {
        // look ahead one char
        let after: String = line_str
            .chars()
            .skip(col + 1)
            .take_while(|c| c.is_ascii_alphabetic())
            .collect();
        if !after.is_empty() {
            if let Some(md) = morpheme_info(&after) {
                return Some(simple_hover(md));
            }
        }
    }
    // c) ident → consult typecheck JSON
    if word.chars().all(|c| c.is_alphanumeric() || c == '_') && !word.is_empty() {
        if let Ok(j) = shim.typecheck(uri, text).await {
            if let Some(md) = type_for_ident(&j, &word, pos) {
                return Some(Hover {
                    contents: HoverContents::Markup(MarkupContent {
                        kind: MarkupKind::Markdown,
                        value: md,
                    }),
                    range: Some(Range { start: pos, end: pos }),
                });
            }
        }
    }
    None
}

fn simple_hover(md: String) -> Hover {
    Hover {
        contents: HoverContents::Markup(MarkupContent {
            kind: MarkupKind::Markdown,
            value: md,
        }),
        range: None,
    }
}

fn line_at(text: &str, line: usize) -> Option<(String, usize)> {
    text.lines().nth(line).map(|l| (l.to_string(), 0))
}

fn word_around(line: &str, col: usize) -> String {
    let chars: Vec<char> = line.chars().collect();
    if chars.is_empty() {
        return String::new();
    }
    let idx = col.min(chars.len().saturating_sub(1));
    // Expand left + right while character is identifier-ish OR "'".
    let is_id = |c: char| c.is_alphanumeric() || c == '_' || c == '\'';
    let mut left = idx;
    while left > 0 && is_id(chars[left - 1]) {
        left -= 1;
    }
    let mut right = idx;
    while right < chars.len() && is_id(chars[right]) {
        right += 1;
    }
    if left == right {
        return chars.get(idx).copied().unwrap_or(' ').to_string();
    }
    chars[left..right].iter().collect()
}

// ---------- 74-glyph hover-table (exhaustive subset) ----------
// Selected high-value glyphs ; the full master-table lives in
// specs/12_TOKENIZER.csl. This is a hover-only synopsis — we use short
// markdown blocks.

fn glyph_info(c: char) -> Option<String> {
    let (name, ascii, category, descr) = match c {
        '§' => ("section", "S:", "structural", "section header"),
        '¶' => ("paragraph", "P:", "structural", "paragraph header"),
        '→' => ("arrow-right", "->", "relation", "maps to / flow"),
        '←' => ("arrow-left", "<-", "relation", "is mapped from"),
        '↔' => ("iff", "<->", "relation", "bidirectional / iff"),
        '≤' => ("less-or-equal", "<=", "comparison", "less-than-or-equal"),
        '≥' => ("greater-or-equal", ">=", "comparison", "greater-than-or-equal"),
        '≠' => ("not-equal", "!=", "comparison", "not equal"),
        '∧' => ("and", "&&", "logical", "logical and (conjunction)"),
        '∨' => ("or", "||", "logical", "logical or (disjunction)"),
        '¬' => ("not", "!", "logical", "logical negation"),
        '∀' => ("forall", "forall", "quantifier", "universal quantifier"),
        '∃' => ("exists", "exists", "quantifier", "existential quantifier"),
        '∈' => ("in", "in", "set", "membership"),
        '⊆' => ("subset-eq", "<=:", "set", "subset or equal"),
        '⊂' => ("subset", "<:", "set", "proper subset"),
        '∪' => ("union", "|+|", "set", "set union"),
        '∩' => ("intersection", "|&|", "set", "set intersection"),
        '⇒' => ("implies", "=>", "logical", "implies / entails"),
        '∵' => ("because", "bc", "reasoning", "because / reason"),
        '∴' => ("therefore", "tf", "reasoning", "therefore / conclusion"),
        '⊗' => ("bahuvrihi", "X%", "compound", "having (bahuvrihi compound)"),
        '⊕' => ("xor", "^", "logical", "exclusive or"),
        '✓' => ("check", "v/", "evidence", "confirmed / proven"),
        '✗' => ("cross", "x/", "evidence", "failed / rejected"),
        '◐' => ("partial", "o/", "evidence", "partial / probable"),
        '○' => ("pending", ".o", "evidence", "pending / possible"),
        '⊘' => ("unknown", "?/", "evidence", "unknown / undecided"),
        '△' => ("caution", "!?", "evidence", "caution / warning-soft"),
        '▽' => ("down-triangle", "!v", "evidence", "soft-refutation"),
        '‼' => ("emphatic", "!!", "evidence", "emphatic / strongly-proven"),
        '⟨' => ("lang", "<{", "bracket", "angle-left (entity/effect)"),
        '⟩' => ("rang", "}>", "bracket", "angle-right (entity/effect)"),
        '⌈' => ("lceil", "(|", "bracket", "ceiling / constraint-lower"),
        '⌉' => ("rceil", "|)", "bracket", "ceiling / constraint-upper"),
        '⟦' => ("lsem", "[[", "bracket", "formula / equation open"),
        '⟧' => ("rsem", "]]", "bracket", "formula / equation close"),
        '«' => ("lguil", "<<", "bracket", "external / API open"),
        '»' => ("rguil", ">>", "bracket", "external / API close"),
        '⟪' => ("l2guil", "<<<", "bracket", "temporal / phase open"),
        '⟫' => ("r2guil", ">>>", "bracket", "temporal / phase close"),
        '∫' => ("integral", "int", "domain", "continuous field"),
        '⊞' => ("box-plus", "[+]", "domain", "spatial / discrete grid"),
        '⊑' => ("lattice-le", "[<=]", "lattice", "sublattice / refinement"),
        '⊔' => ("lattice-join", "[|]", "lattice", "join / least-upper-bound"),
        '⊓' => ("lattice-meet", "[&]", "lattice", "meet / greatest-lower-bound"),
        'λ' => ("lambda", "\\", "abstraction", "lambda-abstraction"),
        'π' => ("projection", "pj", "operator", "projection"),
        'μ' => ("mu", "mu", "operator", "μ-recursion / fixpoint"),
        'ν' => ("nu", "nu", "operator", "ν-greatest fixpoint"),
        'α' | 'β' | 'γ' | 'δ' | 'ε' | 'ζ' | 'η' | 'θ' => {
            ("type-var", "greek", "type", "type-variable (Greek letter convention)")
        }
        _ => return None,
    };

    Some(format!(
        "**{glyph}** — `{name}`\n\n- ASCII alias : `{ascii}`\n- Unicode : `U+{cp:04X}`\n- Category : *{cat}*\n- {descr}",
        glyph = c,
        name = name,
        ascii = ascii,
        cp = c as u32,
        cat = category,
        descr = descr,
    ))
}

// ---------- morpheme hover ----------

fn morpheme_info(tag: &str) -> Option<String> {
    let short = match tag {
        "d" | "durative" | "dur" => "d",
        "f" | "final" | "fin" => "f",
        "s" | "state" => "s",
        "t" | "transitive" | "trans" => "t",
        "e" | "experiential" | "exp" => "e",
        "m" | "modal" | "mod" => "m",
        "p" | "perfective" | "perf" => "p",
        "g" | "generic" | "gen" => "g",
        "r" | "reflexive" | "refl" => "r",
        _ => return None,
    };
    let (name, slot, refinement, docs) = match short {
        "d" => ("durative", "Aspect", "{v | duration(v) > 0}", "04_MORPHEMES.csl §§ durative"),
        "f" => ("final", "Aspect", "{v | terminal(v)}", "04_MORPHEMES.csl §§ final"),
        "s" => ("state", "Kind", "StateTag<ref T>", "04_MORPHEMES.csl §§ state"),
        "t" => ("transitive", "Arity", "{v | arity(v) ≥ 2}", "04_MORPHEMES.csl §§ transitive"),
        "e" => ("experiential", "Evidence", "{v | observed-by(v, a)}", "04_MORPHEMES.csl §§ experiential"),
        "m" => ("modal", "Mood", "Modal<kind>", "04_MORPHEMES.csl §§ modal"),
        "p" => ("perfective", "Aspect", "{v | completed(v)}", "04_MORPHEMES.csl §§ perfective"),
        "g" => ("generic", "Quant", "∀α. P(α)", "04_MORPHEMES.csl §§ generic"),
        "r" => ("reflexive", "Voice", "{v | subject(v) = object(v)}", "04_MORPHEMES.csl §§ reflexive"),
        _ => unreachable!(),
    };
    Some(format!(
        "**Morpheme `'{s}` — `{n}`**\n\n- Slot : *{slot}*\n- Refinement : `{rf}`\n- Docs : `{d}`",
        s = short,
        n = name,
        slot = slot,
        rf = refinement,
        d = docs,
    ))
}

// ---------- type-info via typecheck JSON ----------

fn type_for_ident(j: &J, ident: &str, _pos: Position) -> Option<String> {
    // Our --typecheck --json currently emits diags ; full per-Node type-map
    // would require a CLI extension. For now, we try the globals array if present,
    // falling back to the diag-message fallback.
    if let Some(globals) = j.get("globals").and_then(J::as_object) {
        if let Some(t) = globals.get(ident).and_then(J::as_str) {
            return Some(format!("**`{i}` : `{t}`**", i = ident, t = t));
        }
    }
    if let Some(diags) = j.get("diags").and_then(J::as_array) {
        for d in diags {
            let msg = d.get("msg").and_then(J::as_str).unwrap_or("");
            if msg.contains(ident) && (msg.contains(':') || msg.contains("type")) {
                return Some(format!(
                    "**`{i}` — type info (from diagnostic)**\n\n```\n{m}\n```",
                    i = ident,
                    m = msg,
                ));
            }
        }
    }
    None
}
