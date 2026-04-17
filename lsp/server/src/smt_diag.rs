// § CSLv3 LSP — SMT diagnostics + code-lens (T24.h Session-9)
// I> on save : run parser --smt --json → counter-example diagnostics
// I> code-lens : per-function "discharge SMT obligations" action for
//                 on-demand SMT when smt_on_save is off

use crate::config::Config;
use crate::parser_shim::ParserShim;
use serde_json::Value as J;
use tower_lsp::lsp_types::{
    CodeLens, Command, Position, Range, Url,
};

pub async fn code_lenses(shim: &ParserShim, uri: Url, text: String, cfg: &Config) -> Vec<CodeLens> {
    let mut out = Vec::new();
    // Walk the IR to find fn-ops ; one code-lens per fn.
    let ir = match shim.ir(uri.as_str(), &text).await {
        Ok(j) => j,
        Err(_) => return out,
    };
    let ops = match ir.get("ops").and_then(J::as_array) {
        Some(a) => a,
        None => return out,
    };
    for op in ops {
        if op.get("name").and_then(J::as_str) != Some("cslv3.fn") {
            continue;
        }
        let line = op
            .get("pos")
            .and_then(|p| p.get("line"))
            .and_then(J::as_i64)
            .unwrap_or(1)
            .saturating_sub(1)
            .max(0) as u32;
        out.push(CodeLens {
            range: Range {
                start: Position { line, character: 0 },
                end: Position { line, character: 0 },
            },
            command: Some(Command {
                title: "§ SMT : discharge".to_string(),
                command: "cslv3.smt.discharge".to_string(),
                arguments: Some(vec![serde_json::json!({
                    "uri": uri.to_string(),
                    "line": line,
                })]),
            }),
            data: None,
        });
        if cfg.show_opt_stats && cfg.opt_level >= 0 {
            out.push(CodeLens {
                range: Range {
                    start: Position { line, character: 0 },
                    end: Position { line, character: 0 },
                },
                command: Some(Command {
                    title: format!("§ opt -O{}", cfg.opt_level),
                    command: "cslv3.opt.showStats".to_string(),
                    arguments: Some(vec![serde_json::json!({
                        "uri": uri.to_string(),
                        "opt_level": cfg.opt_level,
                    })]),
                }),
                data: None,
            });
        }
    }
    out
}
