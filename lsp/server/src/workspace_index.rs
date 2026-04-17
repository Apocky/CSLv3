// § CSLv3 LSP — workspace-symbol index (T24.g Session-9)
// I> in-memory symbol-table keyed by name → [(uri, range, kind)]
// I> SQLite-backed persistence is Session-10+ ; current in-memory
// I> populated by parser_shim's IR-walk on-demand
// I> fuzzy workspace/symbol via simple substring + optional Levenshtein

use dashmap::DashMap;
use tower_lsp::lsp_types::{Location, Position, Range, SymbolInformation, SymbolKind, Url};

#[derive(Debug, Clone)]
pub struct Symbol {
    pub name: String,
    pub uri:  Url,
    pub range: Range,
    pub kind: SymbolKind,
    pub is_definition: bool,
}

#[derive(Debug, Default)]
pub struct WorkspaceIndex {
    pub by_name: DashMap<String, Vec<Symbol>>,
}

impl WorkspaceIndex {
    pub fn new_in_memory() -> Self {
        Self::default()
    }

    #[allow(dead_code)] // reserved : populated by didChangeWatchedFiles walker
    pub fn add(&self, sym: Symbol) {
        self.by_name.entry(sym.name.clone()).or_default().push(sym);
    }

    pub fn find_definition(&self, name: &str) -> Option<Location> {
        let entry = self.by_name.get(name)?;
        for s in entry.iter() {
            if s.is_definition {
                return Some(Location {
                    uri: s.uri.clone(),
                    range: s.range,
                });
            }
        }
        entry.iter().next().map(|s| Location {
            uri: s.uri.clone(),
            range: s.range,
        })
    }

    pub fn find_references(&self, name: &str) -> Vec<Location> {
        self.by_name
            .get(name)
            .map(|v| {
                v.iter()
                    .map(|s| Location {
                        uri: s.uri.clone(),
                        range: s.range,
                    })
                    .collect()
            })
            .unwrap_or_default()
    }

    pub fn workspace_symbols(&self, query: &str) -> Vec<SymbolInformation> {
        let q_lower = query.to_lowercase();
        let mut results: Vec<(usize, SymbolInformation)> = Vec::new();
        for entry in self.by_name.iter() {
            let name = entry.key();
            if !name.to_lowercase().contains(&q_lower) && !q_lower.is_empty() {
                // Allow Levenshtein-2 fuzzy match for short queries.
                if q_lower.len() <= 8
                    && levenshtein::levenshtein(&name.to_lowercase(), &q_lower) > 2
                {
                    continue;
                }
            }
            for s in entry.value().iter().filter(|s| s.is_definition) {
                #[allow(deprecated)]
                let info = SymbolInformation {
                    name: s.name.clone(),
                    kind: s.kind,
                    tags: None,
                    deprecated: None,
                    location: Location {
                        uri: s.uri.clone(),
                        range: s.range,
                    },
                    container_name: None,
                };
                let score = if s.name == query {
                    0
                } else if s.name.starts_with(query) {
                    1
                } else {
                    2
                };
                results.push((score, info));
            }
        }
        results.sort_by_key(|(score, _)| *score);
        results.into_iter().map(|(_, v)| v).collect()
    }
}

#[allow(dead_code)]
fn dummy_range() -> Range {
    Range {
        start: Position { line: 0, character: 0 },
        end: Position { line: 0, character: 0 },
    }
}
