// § CSLv3 LSP — diagnostics pipeline (T24.d Session-9)
// I> cssllint JSON → Vec<Diagnostic>
// I> severity mapping : CSL-E-* Error • CSL-W-* Warning • CSL-I-* Information
// I> permissive-accept → Hint ; SMT counter-example → Error w/ related-info

use serde_json::Value as J;
use tower_lsp::lsp_types::{
    Diagnostic, DiagnosticRelatedInformation, DiagnosticSeverity, Location, NumberOrString,
    Position, Range, Url,
};

pub fn diagnostics_from_cssllint(j: &J, uri: &Url) -> Vec<Diagnostic> {
    let mut out = Vec::new();
    let diags = match j.get("diags").and_then(J::as_array) {
        Some(v) => v,
        None => return out,
    };
    for d in diags {
        if let Some(diag) = map_cssllint_entry(d, uri) {
            out.push(diag);
        }
    }
    out
}

fn map_cssllint_entry(d: &J, _uri: &Url) -> Option<Diagnostic> {
    let line = d.get("line")?.as_i64()?.saturating_sub(1).max(0) as u32;
    let col = d.get("col")?.as_i64()?.saturating_sub(1).max(0) as u32;
    let msg = d
        .get("msg")
        .and_then(J::as_str)
        .unwrap_or("CSLv3 diagnostic")
        .to_string();
    let code = d.get("code").and_then(J::as_str).unwrap_or("").to_string();
    let severity = map_severity(d.get("sev").and_then(J::as_str), &code);

    Some(Diagnostic {
        range: Range {
            start: Position { line, character: col },
            end: Position {
                line,
                character: col + 1,
            },
        },
        severity: Some(severity),
        code: if code.is_empty() {
            None
        } else {
            Some(NumberOrString::String(code.clone()))
        },
        code_description: None,
        source: Some("cslv3".to_string()),
        message: msg,
        related_information: None,
        tags: None,
        data: None,
    })
}

fn map_severity(sev: Option<&str>, code: &str) -> DiagnosticSeverity {
    // explicit cssllint sev wins
    match sev {
        Some("error") => return DiagnosticSeverity::ERROR,
        Some("warn") => return DiagnosticSeverity::WARNING,
        Some("info") => return DiagnosticSeverity::INFORMATION,
        Some("hint") => return DiagnosticSeverity::HINT,
        _ => {}
    }
    // fallback : code-prefix mapping
    if code.starts_with("CSL-E-") {
        DiagnosticSeverity::ERROR
    } else if code.starts_with("CSL-W-") {
        if code.contains("PERMISSIVE") || code.contains("007") {
            DiagnosticSeverity::HINT
        } else {
            DiagnosticSeverity::WARNING
        }
    } else if code.starts_with("CSL-I-") {
        DiagnosticSeverity::INFORMATION
    } else {
        DiagnosticSeverity::WARNING
    }
}

/// Merge multiple diagnostic sources into one ordered list, deduplicating by
/// (line, col, code, message). Keeps first occurrence ordering.
pub fn merge(lists: Vec<Vec<Diagnostic>>) -> Vec<Diagnostic> {
    let mut out: Vec<Diagnostic> = Vec::new();
    let mut seen = std::collections::HashSet::new();
    for list in lists {
        for d in list {
            let key = (
                d.range.start.line,
                d.range.start.character,
                d.code.clone().map(|c| match c {
                    NumberOrString::Number(n) => n.to_string(),
                    NumberOrString::String(s) => s,
                }),
                d.message.clone(),
            );
            if seen.insert(key) {
                out.push(d);
            }
        }
    }
    out
}

/// Convert an SMT-JSON response into diagnostics : one per failing obligation.
pub fn diagnostics_from_smt(j: &J, uri: &Url) -> Vec<Diagnostic> {
    let mut out = Vec::new();
    let obs = match j.get("obligations").and_then(J::as_array) {
        Some(v) => v,
        None => return out,
    };
    for o in obs {
        let ok = o.get("ok").and_then(J::as_bool).unwrap_or(true);
        if ok {
            continue;
        }
        let line = o
            .get("line")
            .and_then(J::as_i64)
            .unwrap_or(1)
            .saturating_sub(1)
            .max(0) as u32;
        let col = o
            .get("col")
            .and_then(J::as_i64)
            .unwrap_or(1)
            .saturating_sub(1)
            .max(0) as u32;
        let kind = o.get("kind").and_then(J::as_str).unwrap_or("smt");
        let result = o.get("result").and_then(J::as_str).unwrap_or("?");
        let ctx = o.get("ctx").and_then(J::as_str).unwrap_or("");
        let solver = o.get("solver").and_then(J::as_str).unwrap_or("?");
        let msg = format!(
            "SMT {kind} failed: {result} via {solver} — {ctx}",
            kind = kind,
            result = result,
            solver = solver,
            ctx = ctx
        );

        let d = Diagnostic {
            range: Range {
                start: Position { line, character: col },
                end: Position {
                    line,
                    character: col + 1,
                },
            },
            severity: Some(DiagnosticSeverity::ERROR),
            code: Some(NumberOrString::String("CSL-E-4xx-smt".to_string())),
            code_description: None,
            source: Some(format!("cslv3-smt/{}", solver)),
            message: msg,
            related_information: Some(vec![DiagnosticRelatedInformation {
                location: Location {
                    uri: uri.clone(),
                    range: Range {
                        start: Position { line, character: col },
                        end: Position {
                            line,
                            character: col + 1,
                        },
                    },
                },
                message: format!("counter-example from {solver}"),
            }]),
            tags: None,
            data: None,
        };
        out.push(d);
    }
    out
}
