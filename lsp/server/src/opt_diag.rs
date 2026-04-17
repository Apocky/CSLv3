// § CSLv3 LSP — opt-stats surfacing (T24.h Session-9)
// I> consumes --ir --opt=X --stats --json pass_stats payload
// I> emits one Information diag per pass w/ applied-count (opt-in)
// I> future : per-fn code-lens "optimized N% @ O2" when per-fn stats-attr
//            emitted by parser

use serde_json::Value as J;
use tower_lsp::lsp_types::{
    Diagnostic, DiagnosticSeverity, NumberOrString, Position, Range, Url,
};

pub fn diagnostics_from_opt_stats(j: &J, _uri: &Url) -> Vec<Diagnostic> {
    let mut out = Vec::new();
    let stats = match j.get("pass_stats").and_then(|s| s.get("passes")).and_then(J::as_object) {
        Some(m) => m,
        None => return out,
    };
    for (name, data) in stats {
        let applied = data.get("applied").and_then(J::as_i64).unwrap_or(0);
        if applied == 0 {
            continue;
        }
        let skipped = data.get("skipped").and_then(J::as_i64).unwrap_or(0);
        let ms = data.get("ms").and_then(J::as_i64).unwrap_or(0);
        out.push(Diagnostic {
            range: Range {
                start: Position { line: 0, character: 0 },
                end: Position { line: 0, character: 0 },
            },
            severity: Some(DiagnosticSeverity::INFORMATION),
            code: Some(NumberOrString::String(format!("CSL-I-5xx-opt-{}", name))),
            code_description: None,
            source: Some("cslv3-opt".to_string()),
            message: format!(
                "pass {name}: applied={applied} skipped={skipped} ms={ms}",
                name = name,
                applied = applied,
                skipped = skipped,
                ms = ms,
            ),
            related_information: None,
            tags: None,
            data: None,
        });
    }
    out
}
