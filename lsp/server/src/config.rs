// § CSLv3 LSP — configuration (T24 Session-9)
// I> CLI flags + workspace settings ; runtime-mutable for didChangeConfiguration
// I> pinned paths : parser.exe + Z3 + CVC5 (auto-probed)

use std::env;
use std::path::PathBuf;

#[derive(Debug, Clone, Default)]
pub struct Config {
    pub transport:    Transport,
    pub parser_path:  PathBuf,
    pub z3_path:      PathBuf,
    pub cvc5_path:    PathBuf,
    /// lint / default / strict — matches parser --severity flag family
    pub severity:     Severity,
    /// ms debounce for didChange → re-parse
    pub debounce_ms:  u64,
    /// Toggle SMT-on-save (when false, SMT via code-lens only)
    pub smt_on_save:  bool,
    /// Toggle opt-stats surfacing as Info-diags
    pub show_opt_stats: bool,
    /// opt-level for diagnostic pipeline (0..=3 ; -1 disables opt pipeline)
    pub opt_level:    i32,
}

#[derive(Debug, Clone)]
#[derive(Default)]
pub enum Transport {
    #[default]
    Stdio,
    Tcp(String),
}


#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[derive(Default)]
pub enum Severity {
    Lint,
    #[default]
    Default,
    Strict,
}


impl Severity {
    #[allow(dead_code)] // reserved : driven by CLI flag → parser.exe flag mapping
    pub fn to_flag(self) -> Option<&'static str> {
        match self {
            Severity::Lint => Some("--lint"),
            Severity::Strict => Some("--strict"),
            Severity::Default => None,
        }
    }
}

pub fn parse_cli(args: &[String]) -> Config {
    let mut c = Config {
        debounce_ms: 200,
        opt_level: -1, // disabled by default to keep latency low
        parser_path: find_parser(),
        z3_path: find_solver("z3"),
        cvc5_path: find_solver("cvc5"),
        ..Default::default()
    };

    for a in &args[1..] {
        if a == "--stdio" {
            c.transport = Transport::Stdio;
        } else if let Some(addr) = a.strip_prefix("--tcp=") {
            c.transport = Transport::Tcp(addr.to_string());
        } else if let Some(p) = a.strip_prefix("--parser-path=") {
            c.parser_path = PathBuf::from(p);
        } else if let Some(p) = a.strip_prefix("--z3=") {
            c.z3_path = PathBuf::from(p);
        } else if let Some(p) = a.strip_prefix("--cvc5=") {
            c.cvc5_path = PathBuf::from(p);
        } else if a == "--smt-on-save" {
            c.smt_on_save = true;
        } else if a == "--show-opt-stats" {
            c.show_opt_stats = true;
        } else if let Some(lvl) = a.strip_prefix("--opt-level=") {
            c.opt_level = lvl.parse().unwrap_or(-1);
        } else if let Some(s) = a.strip_prefix("--severity=") {
            c.severity = match s {
                "lint" => Severity::Lint,
                "strict" => Severity::Strict,
                _ => Severity::Default,
            };
        }
    }
    c
}

fn find_parser() -> PathBuf {
    if let Ok(p) = env::var("CSLV3_PARSER") {
        let pb = PathBuf::from(p);
        if pb.exists() {
            return pb;
        }
    }
    // Search cwd first then PATH-like candidates.
    for cand in &[
        "parser.exe",
        "./parser.exe",
        "../parser.exe",
        "../../parser.exe",
    ] {
        let pb = PathBuf::from(cand);
        if pb.exists() {
            return pb;
        }
    }
    PathBuf::from("parser.exe")
}

fn find_solver(name: &str) -> PathBuf {
    let env_key = match name {
        "z3" => "Z3_PATH",
        "cvc5" => "CVC5_PATH",
        _ => return PathBuf::new(),
    };
    if let Ok(p) = env::var(env_key) {
        let pb = PathBuf::from(p);
        if pb.exists() {
            return pb;
        }
    }
    let local = PathBuf::from(format!(
        "{}/AppData/Local/{}",
        env::var("USERPROFILE").unwrap_or_default(),
        name
    ));
    if local.exists() {
        // Shallow recursive search for <name>.exe
        if let Some(found) = recursive_find_exe(&local, &format!("{}.exe", name)) {
            return found;
        }
    }
    PathBuf::new()
}

fn recursive_find_exe(root: &std::path::Path, target: &str) -> Option<PathBuf> {
    let entries = std::fs::read_dir(root).ok()?;
    for e in entries.flatten() {
        let p = e.path();
        if p.is_dir() {
            if let Some(found) = recursive_find_exe(&p, target) {
                return Some(found);
            }
        } else if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
            if name.eq_ignore_ascii_case(target) {
                return Some(p);
            }
        }
    }
    None
}
