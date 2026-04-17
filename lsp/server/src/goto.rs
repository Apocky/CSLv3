// § CSLv3 LSP — goto-definition + references + documentSymbol (T24.g Session-9)
// I> symbol extraction walks the IR-JSON ops ; names come from attr "name"
//    (cslv3.fn) or cslv3.var_ref
// I> references : same-file use-sites from IR ; cross-file via WorkspaceIndex
// I> documentSymbol : tree-by-region-nesting

use crate::parser_shim::ParserShim;
use crate::workspace_index::WorkspaceIndex;
use serde_json::Value as J;
use tower_lsp::lsp_types::{
    DocumentSymbol, GotoDefinitionResponse, Location, Position, Range, SymbolKind, Url,
};

pub async fn definition_at(
    shim: &ParserShim,
    index: &WorkspaceIndex,
    uri: &Url,
    text: &str,
    pos: Position,
) -> Option<GotoDefinitionResponse> {
    let ident = word_at(text, pos)?;
    // same-file
    if let Ok(ir) = shim.ir(uri.as_str(), text).await {
        if let Some(rng) = find_fn_definition(&ir, &ident) {
            return Some(GotoDefinitionResponse::Scalar(Location {
                uri: uri.clone(),
                range: rng,
            }));
        }
    }
    // cross-file via index
    if let Some(loc) = index.find_definition(&ident) {
        return Some(GotoDefinitionResponse::Scalar(loc));
    }
    None
}

pub async fn references_at(
    shim: &ParserShim,
    index: &WorkspaceIndex,
    uri: &Url,
    text: &str,
    pos: Position,
) -> Option<Vec<Location>> {
    let ident = word_at(text, pos)?;
    let mut out = Vec::new();
    if let Ok(ir) = shim.ir(uri.as_str(), text).await {
        out.extend(find_references_in_ir(&ir, &ident, uri));
    }
    out.extend(index.find_references(&ident));
    Some(out)
}

pub async fn document_symbols(shim: &ParserShim, text: &str) -> Vec<DocumentSymbol> {
    let ir = match shim.ir("file://in-memory", text).await {
        Ok(j) => j,
        Err(_) => return Vec::new(),
    };
    let mut out = Vec::new();
    if let Some(ops) = ir.get("ops").and_then(J::as_array) {
        for op in ops {
            if let Some(sym) = op_to_symbol(op) {
                out.push(sym);
            }
        }
    }
    out
}

fn op_to_symbol(op: &J) -> Option<DocumentSymbol> {
    let name = op
        .get("attrs")
        .and_then(|a| a.get("name"))
        .and_then(|n| n.get("value"))
        .and_then(J::as_str)?
        .to_string();
    let op_name = op.get("name").and_then(J::as_str).unwrap_or("op").to_string();
    let kind = match op_name.as_str() {
        "cslv3.fn" => SymbolKind::FUNCTION,
        "cslv3.var_ref" => SymbolKind::VARIABLE,
        _ => SymbolKind::OBJECT,
    };
    let pos = op.get("pos").cloned().unwrap_or(J::Null);
    let line = pos.get("line").and_then(J::as_i64).unwrap_or(1).saturating_sub(1).max(0) as u32;
    let col = pos.get("col").and_then(J::as_i64).unwrap_or(1).saturating_sub(1).max(0) as u32;

    #[allow(deprecated)]
    Some(DocumentSymbol {
        name,
        detail: Some(op_name),
        kind,
        range: Range {
            start: Position { line, character: col },
            end: Position {
                line,
                character: col + 1,
            },
        },
        selection_range: Range {
            start: Position { line, character: col },
            end: Position {
                line,
                character: col + 1,
            },
        },
        children: None,
        tags: None,
        deprecated: None,
    })
}

fn find_fn_definition(ir: &J, name: &str) -> Option<Range> {
    let ops = ir.get("ops").and_then(J::as_array)?;
    for op in ops {
        if op.get("name").and_then(J::as_str) != Some("cslv3.fn") {
            continue;
        }
        let op_name = op
            .get("attrs")
            .and_then(|a| a.get("name"))
            .and_then(|n| n.get("value"))
            .and_then(J::as_str);
        if op_name == Some(name) {
            let pos = op.get("pos")?;
            let line = pos.get("line").and_then(J::as_i64).unwrap_or(1).saturating_sub(1).max(0) as u32;
            let col = pos.get("col").and_then(J::as_i64).unwrap_or(1).saturating_sub(1).max(0) as u32;
            return Some(Range {
                start: Position { line, character: col },
                end: Position {
                    line,
                    character: col + name.chars().count() as u32,
                },
            });
        }
    }
    None
}

fn find_references_in_ir(ir: &J, name: &str, uri: &Url) -> Vec<Location> {
    let mut out = Vec::new();
    if let Some(ops) = ir.get("ops").and_then(J::as_array) {
        for op in ops {
            collect_refs_in_op(op, name, uri, &mut out);
        }
    }
    out
}

fn collect_refs_in_op(op: &J, name: &str, uri: &Url, out: &mut Vec<Location>) {
    // Check attrs["name"] matches name
    if let Some(nm_attr) = op.get("attrs").and_then(|a| a.get("name")).and_then(|n| n.get("value")) {
        if nm_attr.as_str() == Some(name) {
            if let Some(pos) = op.get("pos") {
                let line = pos.get("line").and_then(J::as_i64).unwrap_or(1).saturating_sub(1).max(0) as u32;
                let col = pos.get("col").and_then(J::as_i64).unwrap_or(1).saturating_sub(1).max(0) as u32;
                out.push(Location {
                    uri: uri.clone(),
                    range: Range {
                        start: Position { line, character: col },
                        end: Position {
                            line,
                            character: col + name.chars().count() as u32,
                        },
                    },
                });
            }
        }
    }
    // Recurse into regions → blocks → ops
    if let Some(regions) = op.get("regions").and_then(J::as_array) {
        for r in regions {
            if let Some(blocks) = r.get("blocks").and_then(J::as_array) {
                for b in blocks {
                    if let Some(ops2) = b.get("ops").and_then(J::as_array) {
                        for inner in ops2 {
                            collect_refs_in_op(inner, name, uri, out);
                        }
                    }
                }
            }
        }
    }
}

fn word_at(text: &str, pos: Position) -> Option<String> {
    let line = text.lines().nth(pos.line as usize)?;
    let chars: Vec<char> = line.chars().collect();
    if chars.is_empty() {
        return None;
    }
    let col = (pos.character as usize).min(chars.len().saturating_sub(1));
    let is_id = |c: char| c.is_alphanumeric() || c == '_' || c == '-';
    let mut left = col;
    while left > 0 && is_id(chars[left - 1]) {
        left -= 1;
    }
    let mut right = col;
    while right < chars.len() && is_id(chars[right]) {
        right += 1;
    }
    if left == right {
        return None;
    }
    Some(chars[left..right].iter().collect())
}
