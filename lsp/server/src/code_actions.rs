// § CSLv3 LSP — code-actions + quick-fixes (T24 Session-9)
// I> dispatch on diag.code strings from cssllint/typecheck/SMT/opt
// I> quick-fixes :
//    unknown-morpheme → suggest-nearest (Levenshtein against 9-list)
//    permissive-accept → promote-to-strict
//    type-mismatch → insert-cast (when applicable)

use tower_lsp::lsp_types::{
    CodeAction, CodeActionKind, CodeActionOrCommand, CodeActionParams, CodeActionResponse,
    Diagnostic, NumberOrString, Position, Range, TextEdit, Url, WorkspaceEdit,
};

pub fn actions_for(p: &CodeActionParams) -> CodeActionResponse {
    let mut out = Vec::<CodeActionOrCommand>::new();
    for d in &p.context.diagnostics {
        out.extend(actions_for_diag(d, &p.text_document.uri));
    }
    out
}

fn actions_for_diag(d: &Diagnostic, uri: &Url) -> Vec<CodeActionOrCommand> {
    let code = match &d.code {
        Some(NumberOrString::String(s)) => s.as_str(),
        _ => return Vec::new(),
    };
    let mut out = Vec::new();

    if code.contains("morph-unknown") || code.starts_with("CSL-W-003") {
        if let Some(best) = nearest_morpheme(&d.message) {
            out.push(CodeActionOrCommand::CodeAction(CodeAction {
                title: format!("Change morpheme to '{}'", best),
                kind: Some(CodeActionKind::QUICKFIX),
                diagnostics: Some(vec![d.clone()]),
                edit: Some(simple_edit(
                    uri,
                    d.range,
                    format!("'{}", best),
                )),
                is_preferred: Some(true),
                ..Default::default()
            }));
        }
    }

    if code.contains("permissive") || code.starts_with("CSL-W-007") {
        out.push(CodeActionOrCommand::CodeAction(CodeAction {
            title: "Toggle --strict-parse to promote".to_string(),
            kind: Some(CodeActionKind::SOURCE),
            diagnostics: Some(vec![d.clone()]),
            edit: None,
            command: None,
            is_preferred: Some(false),
            ..Default::default()
        }));
    }

    if code.starts_with("CSL-E-200") {
        // type-mismatch : offer an insert-cast hint
        out.push(CodeActionOrCommand::CodeAction(CodeAction {
            title: "Review type mismatch".to_string(),
            kind: Some(CodeActionKind::QUICKFIX),
            diagnostics: Some(vec![d.clone()]),
            edit: None,
            command: None,
            ..Default::default()
        }));
    }

    out
}

// pick the morpheme (of 9) closest to the offending source text by Levenshtein
fn nearest_morpheme(msg: &str) -> Option<&'static str> {
    // Try to extract the rendered tag from the diagnostic message
    // (cssllint emits e.g. "morpheme 'xyz' unknown").
    let quoted = msg.find('\'').and_then(|i| {
        let rest = &msg[i + 1..];
        rest.find('\'').map(|j| &rest[..j])
    })?;
    const TAGS: &[&str] = &["d", "f", "s", "t", "e", "m", "p", "g", "r"];
    let mut best = "";
    let mut best_dist = usize::MAX;
    for t in TAGS {
        let dist = levenshtein::levenshtein(quoted, t);
        if dist < best_dist {
            best_dist = dist;
            best = *t;
        }
    }
    if best.is_empty() {
        None
    } else {
        Some(best)
    }
}

fn simple_edit(uri: &Url, range: Range, new_text: String) -> WorkspaceEdit {
    use std::collections::HashMap;
    let mut changes: HashMap<Url, Vec<TextEdit>> = HashMap::new();
    changes.insert(uri.clone(), vec![TextEdit { range, new_text }]);
    WorkspaceEdit {
        changes: Some(changes),
        document_changes: None,
        change_annotations: None,
    }
}

#[allow(dead_code)]
fn zero_pos() -> Position {
    Position { line: 0, character: 0 }
}
