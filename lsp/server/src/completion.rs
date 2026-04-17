// § CSLv3 LSP — completion provider (T24.f Session-9)
// I> context-aware via trigger-character analysis :
//    after `'` → 9 morphemes
//    after `§` → modal / think-block headers
//    after `.` / `⊗` / `@` / `+` → compound operators
//    default → keywords + built-ins
// I> snippet-insert for fn / def / enum patterns

use tower_lsp::lsp_types::{
    CompletionContext, CompletionItem, CompletionItemKind, CompletionTriggerKind, Documentation,
    InsertTextFormat, MarkupContent, MarkupKind, Position,
};

pub fn complete_at(text: &str, pos: Position, ctx: Option<&CompletionContext>) -> Vec<CompletionItem> {
    let trigger: Option<char> = ctx
        .and_then(|c| {
            if c.trigger_kind == CompletionTriggerKind::TRIGGER_CHARACTER {
                c.trigger_character
                    .as_ref()
                    .and_then(|s| s.chars().next())
            } else {
                None
            }
        })
        // fallback : inspect char immediately before cursor
        .or_else(|| char_before(text, pos));

    match trigger {
        Some('\'') => morpheme_completions(),
        Some('§') => section_completions(),
        Some('.') => compound_completions_dot(),
        Some('⊗') => compound_completions_having(),
        Some('@') => compound_completions_at(),
        Some('+') => compound_completions_and(),
        Some(':') => type_completions(),
        _ => default_completions(),
    }
}

fn char_before(text: &str, pos: Position) -> Option<char> {
    let line = text.lines().nth(pos.line as usize)?;
    let col = pos.character as usize;
    if col == 0 {
        return None;
    }
    line.chars().nth(col.saturating_sub(1))
}

// ---------- Morpheme completions ----------

fn morpheme_completions() -> Vec<CompletionItem> {
    let morphemes = [
        ("d", "durative",     "{v | duration(v) > 0}"),
        ("f", "final",        "{v | terminal(v)}"),
        ("s", "state",        "StateTag<ref T>"),
        ("t", "transitive",   "{v | arity(v) >= 2}"),
        ("e", "experiential", "{v | observed-by(v, a)}"),
        ("m", "modal",        "Modal<kind>"),
        ("p", "perfective",   "{v | completed(v)}"),
        ("g", "generic",      "∀α. P(α)"),
        ("r", "reflexive",    "{v | subject(v) = object(v)}"),
    ];
    morphemes
        .iter()
        .map(|(tag, name, refinement)| CompletionItem {
            label: (*tag).to_string(),
            kind: Some(CompletionItemKind::KEYWORD),
            detail: Some(format!("morpheme : {}", name)),
            documentation: Some(Documentation::MarkupContent(MarkupContent {
                kind: MarkupKind::Markdown,
                value: format!(
                    "**`'{}` — `{}`**\n\n- Refinement : `{}`",
                    tag, name, refinement
                ),
            })),
            insert_text: Some((*tag).to_string()),
            ..Default::default()
        })
        .collect()
}

// ---------- Section / modal completions ----------

fn section_completions() -> Vec<CompletionItem> {
    let items = [
        ("I>", "insight", "key claim"),
        ("W!", "must",    "hard requirement"),
        ("R!", "should",  "strong recommendation"),
        ("M?", "may",     "optional"),
        ("N!", "mustnt",  "prohibition"),
        ("Q?", "question","open question"),
        ("P",  "problem", "reasoning block : given + goal"),
        ("D",  "decompose", "reasoning block : break goal into subs"),
        ("T",  "trace",   "reasoning block : attempt subs, mark ✓/✗"),
        ("S",  "synthesis", "reasoning block : combine partials"),
        ("C",  "check",   "reasoning block : verify"),
    ];
    items
        .iter()
        .map(|(label, name, descr)| CompletionItem {
            label: (*label).to_string(),
            kind: Some(CompletionItemKind::KEYWORD),
            detail: Some(format!("modal : {}", name)),
            documentation: Some(Documentation::String(descr.to_string())),
            insert_text: Some(format!("{} ", label)),
            ..Default::default()
        })
        .collect()
}

// ---------- Compound operator completions ----------

fn compound_completions_dot() -> Vec<CompletionItem> {
    vec![
        simple("(of)", "tatpuruṣa compound — attributive"),
        simple("prog", "aspect morpheme : progressive"),
        simple("perf", "aspect morpheme : perfective"),
        simple("cert", "certainty morpheme : certain"),
        simple("must", "modality morpheme : must"),
        simple("iter", "aspect morpheme : iterative"),
        simple("hab",  "aspect morpheme : habitual"),
        simple("inch", "aspect morpheme : inchoative"),
        simple("term", "aspect morpheme : terminative"),
        simple("may",  "modality morpheme : may"),
        simple("cant", "modality morpheme : cannot"),
        simple("will", "modality morpheme : will"),
        simple("wont", "modality morpheme : wont"),
        simple("prob", "certainty morpheme : probable"),
        simple("poss", "certainty morpheme : possible"),
        simple("doubt","certainty morpheme : doubtful"),
        simple("loc",  "scope morpheme : local"),
        simple("glob", "scope morpheme : global"),
        simple("ctx",  "scope morpheme : contextual"),
    ]
}

fn compound_completions_having() -> Vec<CompletionItem> {
    vec![simple("(having)", "bahuvrīhi compound — possessive")]
}

fn compound_completions_at() -> Vec<CompletionItem> {
    vec![simple("(at)", "avyayībhāva compound — locative/scope")]
}

fn compound_completions_and() -> Vec<CompletionItem> {
    vec![simple("(and)", "dvandva compound — co-ordinate")]
}

// ---------- Type completions (after `:`) ----------

fn type_completions() -> Vec<CompletionItem> {
    let types = [
        "bool", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64",
        "f32", "f64", "str", "Unit", "Int", "Float", "vec2", "vec3",
        "vec4", "mat4", "quat", "rgba",
    ];
    types
        .iter()
        .map(|t| CompletionItem {
            label: (*t).to_string(),
            kind: Some(CompletionItemKind::TYPE_PARAMETER),
            insert_text: Some((*t).to_string()),
            ..Default::default()
        })
        .collect()
}

// ---------- Default ----------

fn default_completions() -> Vec<CompletionItem> {
    let mut v = vec![
        snippet("fn", "fn ${1:name} (${2:x : T}) -> ${3:T} = $0", "function definition"),
        snippet("def", "def ${1:name} = $0", "value definition"),
        snippet("enum", "enum[ ${1:A}, ${2:B} ]", "variant type"),
        snippet("record", "⟨ ${1:field} : ${2:T} ⟩", "record type"),
        keyword("if", "conditional"),
        keyword("then", "conditional branch"),
        keyword("else", "conditional alternate"),
        keyword("match", "pattern matching"),
        keyword("let", "binding"),
        keyword("fn", "function"),
        keyword("forall", "universal quantifier"),
        keyword("exists", "existential quantifier"),
    ];
    v.extend(morpheme_completions());
    v
}

fn simple(label: &str, descr: &str) -> CompletionItem {
    CompletionItem {
        label: label.to_string(),
        kind: Some(CompletionItemKind::OPERATOR),
        detail: Some(descr.to_string()),
        ..Default::default()
    }
}

fn keyword(label: &str, descr: &str) -> CompletionItem {
    CompletionItem {
        label: label.to_string(),
        kind: Some(CompletionItemKind::KEYWORD),
        detail: Some(descr.to_string()),
        ..Default::default()
    }
}

fn snippet(label: &str, body: &str, descr: &str) -> CompletionItem {
    CompletionItem {
        label: label.to_string(),
        kind: Some(CompletionItemKind::SNIPPET),
        detail: Some(descr.to_string()),
        insert_text: Some(body.to_string()),
        insert_text_format: Some(InsertTextFormat::SNIPPET),
        ..Default::default()
    }
}
