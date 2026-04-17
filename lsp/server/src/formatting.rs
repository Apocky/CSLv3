// § CSLv3 LSP — formatting provider (T24 Session-9)
// I> full-document : parser --print --mode=canonical
// I> range : scoped-extract is Session-10+ ; current falls-back to whole-doc

use crate::parser_shim::ParserShim;
use tower_lsp::lsp_types::{Position, Range, TextEdit};

pub async fn format_document(shim: &ParserShim, text: &str) -> Option<Vec<TextEdit>> {
    let formatted = shim.format(text, "canonical").await.ok()?;
    if formatted == text {
        return Some(Vec::new());
    }
    Some(vec![TextEdit {
        range: full_range(text),
        new_text: formatted,
    }])
}

pub async fn format_range(
    shim: &ParserShim,
    text: &str,
    _range: Range,
) -> Option<Vec<TextEdit>> {
    // v1 : fall through to whole-document format. A proper range-aware
    // pprint requires an AST-subtree-extract path in parser.exe.
    format_document(shim, text).await
}

fn full_range(text: &str) -> Range {
    let line_count = text.lines().count() as u32;
    let last_line_len = text
        .lines()
        .last()
        .map(|l| l.chars().count())
        .unwrap_or(0) as u32;
    Range {
        start: Position { line: 0, character: 0 },
        end: Position {
            line: line_count.saturating_sub(1),
            character: last_line_len,
        },
    }
}
