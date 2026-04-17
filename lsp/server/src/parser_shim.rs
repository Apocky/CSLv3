// § CSLv3 LSP — parser.exe subprocess driver (T24.c Session-9)
// I> shell-out to parser.exe for cssllint + --ir + --smt + --opt queries
// I> cache keyed by (URI, content-hash) so stable content avoids re-spawn
// I> subprocess is synchronous in tokio::task::spawn_blocking to keep the
//    async runtime healthy
// I> timeout : configurable per-call ; graceful-degrade on non-zero exit

use anyhow::{anyhow, Result};
use blake3::Hasher;
use dashmap::DashMap;
use serde_json::Value as J;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Arc;
use std::time::Duration;
use tokio::time::timeout;

#[derive(Clone)]
pub struct ParserShim {
    parser_path: PathBuf,
    /// (uri-content-hash) → last cssllint JSON
    cssllint_cache: Arc<DashMap<String, J>>,
    /// (uri-content-hash) → last IR JSON
    ir_cache: Arc<DashMap<String, J>>,
    /// (uri-content-hash) → last SMT JSON
    smt_cache: Arc<DashMap<String, J>>,
    /// (uri-content-hash) → last typecheck JSON
    tc_cache: Arc<DashMap<String, J>>,
}

impl ParserShim {
    pub fn new(parser_path: PathBuf) -> Self {
        Self {
            parser_path,
            cssllint_cache: Arc::new(DashMap::new()),
            ir_cache: Arc::new(DashMap::new()),
            smt_cache: Arc::new(DashMap::new()),
            tc_cache: Arc::new(DashMap::new()),
        }
    }

    #[allow(dead_code)] // reserved : command-routing diagnostics
    pub fn parser_path(&self) -> &Path {
        &self.parser_path
    }

    /// Compute a cache-key for (URI, content).
    pub fn key(uri: &str, text: &str) -> String {
        let mut h = Hasher::new();
        h.update(uri.as_bytes());
        h.update(b"|");
        h.update(text.as_bytes());
        let d = h.finalize().to_hex();
        d.to_string()
    }

    /// Run cssllint --json on content, returning parsed JSON. Caches on key.
    pub async fn cssllint(&self, uri: &str, text: &str) -> Result<J> {
        let k = Self::key(uri, text);
        if let Some(v) = self.cssllint_cache.get(&k) {
            return Ok(v.clone());
        }
        let parser = self.parser_path.clone();
        let content = text.to_string();
        let fut = tokio::task::spawn_blocking(move || run_with_stdin(&parser, &["cssllint", "--json", "-"], &content));
        let out = timeout(Duration::from_secs(10), fut).await??;
        let out = out?;
        let j: J = serde_json::from_str(&out)
            .map_err(|e| anyhow!("cssllint JSON parse failed: {}\n{}", e, out))?;
        self.cssllint_cache.insert(k, j.clone());
        Ok(j)
    }

    /// Typecheck --json ; caches on key.
    pub async fn typecheck(&self, uri: &str, text: &str) -> Result<J> {
        let k = Self::key(uri, text);
        if let Some(v) = self.tc_cache.get(&k) {
            return Ok(v.clone());
        }
        let parser = self.parser_path.clone();
        let content = text.to_string();
        let fut = tokio::task::spawn_blocking(move || {
            run_with_stdin(&parser, &["--typecheck", "--json", "-"], &content)
        });
        let out = timeout(Duration::from_secs(10), fut).await??;
        let out = out?;
        let j: J = serde_json::from_str(&out)
            .map_err(|e| anyhow!("typecheck JSON parse failed: {}\n{}", e, out))?;
        self.tc_cache.insert(k, j.clone());
        Ok(j)
    }

    /// --ir --json ; caches on key.
    pub async fn ir(&self, uri: &str, text: &str) -> Result<J> {
        let k = Self::key(uri, text);
        if let Some(v) = self.ir_cache.get(&k) {
            return Ok(v.clone());
        }
        let parser = self.parser_path.clone();
        let content = text.to_string();
        let fut = tokio::task::spawn_blocking(move || {
            run_with_stdin(&parser, &["--ir", "--json", "-"], &content)
        });
        let out = timeout(Duration::from_secs(15), fut).await??;
        let out = out?;
        let j: J = serde_json::from_str(&out)
            .map_err(|e| anyhow!("ir JSON parse failed: {}\n{}", e, out))?;
        self.ir_cache.insert(k, j.clone());
        Ok(j)
    }

    /// --smt --json ; caches on key + solver-paths.
    pub async fn smt(&self, uri: &str, text: &str, z3: &Path, cvc5: &Path) -> Result<J> {
        let k = format!("{}:{}:{}", Self::key(uri, text), z3.display(), cvc5.display());
        if let Some(v) = self.smt_cache.get(&k) {
            return Ok(v.clone());
        }
        let parser = self.parser_path.clone();
        let z3_s = z3.display().to_string();
        let cvc5_s = cvc5.display().to_string();
        let content = text.to_string();
        let fut = tokio::task::spawn_blocking(move || {
            let mut args: Vec<String> = vec!["--smt".into(), "--json".into()];
            if !z3_s.is_empty() {
                args.push(format!("--z3={}", z3_s));
            }
            if !cvc5_s.is_empty() {
                args.push(format!("--cvc5={}", cvc5_s));
            }
            args.push("-".into());
            let arg_refs: Vec<&str> = args.iter().map(|s| s.as_str()).collect();
            run_with_stdin(&parser, &arg_refs, &content)
        });
        let out = timeout(Duration::from_secs(30), fut).await??;
        let out = out?;
        let j: J = serde_json::from_str(&out)
            .map_err(|e| anyhow!("smt JSON parse failed: {}\n{}", e, out))?;
        self.smt_cache.insert(k, j.clone());
        Ok(j)
    }

    /// --ir --opt=O2 --stats --json ; caches on key + opt-level.
    pub async fn opt_stats(&self, uri: &str, text: &str, opt_level: i32) -> Result<J> {
        let _k = format!("{}:opt{}", Self::key(uri, text), opt_level);
        if opt_level < 0 {
            return Ok(J::Null);
        }
        let parser = self.parser_path.clone();
        let content = text.to_string();
        let fut = tokio::task::spawn_blocking(move || {
            let opt = format!("--opt=O{}", opt_level);
            run_with_stdin(&parser, &["--ir", "--json", "--stats", &opt, "-"], &content)
        });
        let out = timeout(Duration::from_secs(15), fut).await??;
        let out = out?;
        let j: J = serde_json::from_str(&out)
            .map_err(|e| anyhow!("opt-stats JSON parse failed: {}\n{}", e, out))?;
        Ok(j)
    }

    /// Format via --print --mode=canonical. Returns formatted text.
    pub async fn format(&self, text: &str, mode: &str) -> Result<String> {
        let parser = self.parser_path.clone();
        let content = text.to_string();
        let mode_arg = format!("--mode={}", mode);
        let fut = tokio::task::spawn_blocking(move || {
            run_with_stdin(&parser, &["--print", &mode_arg, "-"], &content)
        });
        let out = timeout(Duration::from_secs(5), fut).await??;
        out
    }

    /// Invalidate ALL caches for a URI (content has changed).
    pub fn invalidate_uri(&self, uri: &str) {
        let prefix = format!("{}|", uri);
        self.cssllint_cache.retain(|k, _| !k.starts_with(&prefix));
        self.ir_cache.retain(|k, _| !k.starts_with(&prefix));
        self.smt_cache.retain(|k, _| !k.starts_with(&prefix));
        self.tc_cache.retain(|k, _| !k.starts_with(&prefix));
    }
}

// ---------- raw subprocess runner ----------

fn run_with_stdin(parser: &Path, args: &[&str], stdin_text: &str) -> Result<String> {
    use std::io::Write;
    use std::process::Stdio;

    // parser.exe doesn't accept "-" as a stdin-file for every mode. Route via
    // tempfile when the args include a trailing "-" placeholder.
    let mut tmp: Option<tempfile::NamedTempFile> = None;
    let final_args: Vec<String> = if args.last() == Some(&"-") {
        let mut f = tempfile::NamedTempFile::with_prefix("cslv3-lsp-")
            .map_err(|e| anyhow!("tempfile: {}", e))?;
        f.write_all(stdin_text.as_bytes())?;
        let path = f.path().to_string_lossy().to_string();
        let mut out: Vec<String> = args[..args.len() - 1].iter().map(|s| s.to_string()).collect();
        out.push(path);
        tmp = Some(f);
        out
    } else {
        args.iter().map(|s| s.to_string()).collect()
    };

    let mut cmd = Command::new(parser);
    cmd.args(&final_args);
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());

    let out = cmd
        .output()
        .map_err(|e| anyhow!("parser.exe spawn failed: {} (path={})", e, parser.display()))?;

    drop(tmp); // best-effort delete

    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    // parser.exe returns nonzero for diagnostics-present files ; stdout still
    // has valid JSON. Don't treat exit-code alone as failure.
    if stdout.trim().is_empty() {
        let stderr = String::from_utf8_lossy(&out.stderr).to_string();
        return Err(anyhow!(
            "parser.exe empty stdout (rc={:?}, stderr={})",
            out.status.code(),
            stderr
        ));
    }
    Ok(stdout)
}
