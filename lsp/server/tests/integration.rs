// § CSLv3 LSP — integration tests (T24.i Session-9)
// I> spawn the server binary via stdio ; exchange JSON-RPC messages ;
//    assert expected responses for initialize + hover + completion
//
// These tests require parser.exe to be reachable (CWD = repo root). The
// Cargo harness runs from lsp/ so we set CSLV3_PARSER to the repo-rooted
// parser.exe.

use std::io::{BufRead, BufReader, Read, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, ChildStdout, Command, Stdio};
use std::sync::atomic::{AtomicI64, Ordering};

static REQ_ID: AtomicI64 = AtomicI64::new(1);

struct Server {
    _child: Child,
    stdin: ChildStdin,
    stdout: BufReader<ChildStdout>,
}

fn find_lsp_bin() -> PathBuf {
    // Cargo places the binary at target/debug/cslv3-lsp.exe relative to the
    // workspace root (lsp/). Tests run with CWD=lsp/server, so walk up.
    for cand in &[
        "../target/debug/cslv3-lsp.exe",
        "../target/debug/cslv3-lsp",
        "target/debug/cslv3-lsp.exe",
        "target/debug/cslv3-lsp",
    ] {
        let pb = PathBuf::from(cand);
        if pb.exists() {
            return pb.canonicalize().unwrap_or(pb);
        }
    }
    panic!("cslv3-lsp binary not found");
}

fn find_parser() -> PathBuf {
    for cand in &[
        "../../parser.exe",
        "../parser.exe",
        "parser.exe",
        "../../../parser.exe",
    ] {
        let pb = PathBuf::from(cand);
        if pb.exists() {
            return pb.canonicalize().unwrap_or(pb);
        }
    }
    panic!("parser.exe not found")
}

fn start_server() -> Server {
    let bin = find_lsp_bin();
    let parser = find_parser();
    let mut child = Command::new(&bin)
        .arg("--stdio")
        .arg(format!("--parser-path={}", parser.display()))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("spawn lsp");
    let stdin = child.stdin.take().unwrap();
    let stdout = BufReader::new(child.stdout.take().unwrap());
    Server {
        _child: child,
        stdin,
        stdout,
    }
}

fn send(stdin: &mut ChildStdin, method: &str, params: serde_json::Value) -> i64 {
    let id = REQ_ID.fetch_add(1, Ordering::SeqCst);
    let msg = serde_json::json!({
        "jsonrpc": "2.0",
        "id": id,
        "method": method,
        "params": params,
    });
    send_raw(stdin, &msg);
    id
}

fn notify(stdin: &mut ChildStdin, method: &str, params: serde_json::Value) {
    let msg = serde_json::json!({
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
    });
    send_raw(stdin, &msg);
}

fn send_raw(stdin: &mut ChildStdin, msg: &serde_json::Value) {
    let s = serde_json::to_string(msg).unwrap();
    let header = format!("Content-Length: {}\r\n\r\n", s.len());
    stdin.write_all(header.as_bytes()).unwrap();
    stdin.write_all(s.as_bytes()).unwrap();
    stdin.flush().unwrap();
}

fn recv(stdout: &mut BufReader<ChildStdout>) -> serde_json::Value {
    // Read Content-Length: N\r\n\r\n then N bytes.
    let mut content_len: usize = 0;
    loop {
        let mut line = String::new();
        stdout.read_line(&mut line).unwrap();
        let line = line.trim_end_matches(['\r', '\n']);
        if line.is_empty() {
            break;
        }
        if let Some(v) = line.strip_prefix("Content-Length:") {
            content_len = v.trim().parse().unwrap_or(0);
        }
    }
    let mut buf = vec![0u8; content_len];
    stdout.read_exact(&mut buf).unwrap();
    serde_json::from_slice(&buf).unwrap()
}

fn wait_response(stdout: &mut BufReader<ChildStdout>, target_id: i64) -> serde_json::Value {
    for _ in 0..50 {
        let msg = recv(stdout);
        if msg.get("id").and_then(|v| v.as_i64()) == Some(target_id) {
            return msg;
        }
        // Notifications (publishDiagnostics) may arrive before the response ;
        // keep reading.
    }
    panic!("no response for id {}", target_id);
}

#[test]
fn test_initialize_handshake() {
    let mut s = start_server();
    let id = send(
        &mut s.stdin,
        "initialize",
        serde_json::json!({
            "processId": null,
            "capabilities": {},
        }),
    );
    let resp = wait_response(&mut s.stdout, id);
    let caps = &resp["result"]["capabilities"];
    assert!(
        caps["hoverProvider"].as_bool().is_some() || caps["hoverProvider"].is_object(),
        "hoverProvider missing in caps: {:?}", caps
    );
    assert!(caps["completionProvider"].is_object(), "completionProvider missing");
    assert!(
        caps["definitionProvider"].as_bool().is_some() || caps["definitionProvider"].is_object(),
        "definitionProvider missing"
    );
    // shutdown + exit
    let sid = send(&mut s.stdin, "shutdown", serde_json::json!({}));
    let _ = wait_response(&mut s.stdout, sid);
    notify(&mut s.stdin, "exit", serde_json::json!({}));
}

#[test]
fn test_hover_glyph() {
    let mut s = start_server();
    let init = send(
        &mut s.stdin,
        "initialize",
        serde_json::json!({
            "processId": null,
            "capabilities": {},
        }),
    );
    let _ = wait_response(&mut s.stdout, init);
    notify(&mut s.stdin, "initialized", serde_json::json!({}));
    let content = "§ T\n  x : i32\n";
    notify(
        &mut s.stdin,
        "textDocument/didOpen",
        serde_json::json!({
            "textDocument": {
                "uri": "file:///test.csl",
                "languageId": "cslv3",
                "version": 1,
                "text": content,
            }
        }),
    );
    // hover at position line=0, col=0 (on '§')
    let hid = send(
        &mut s.stdin,
        "textDocument/hover",
        serde_json::json!({
            "textDocument": { "uri": "file:///test.csl" },
            "position": { "line": 0, "character": 0 },
        }),
    );
    let resp = wait_response(&mut s.stdout, hid);
    let contents = &resp["result"]["contents"];
    let value = contents["value"].as_str().unwrap_or("");
    assert!(
        value.contains("section") || value.contains("Section") || value.contains("§"),
        "hover value lacks section info: {value}"
    );
    let sid = send(&mut s.stdin, "shutdown", serde_json::json!({}));
    let _ = wait_response(&mut s.stdout, sid);
    notify(&mut s.stdin, "exit", serde_json::json!({}));
}

#[test]
fn test_completion_after_apostrophe() {
    let mut s = start_server();
    let init = send(
        &mut s.stdin,
        "initialize",
        serde_json::json!({ "processId": null, "capabilities": {} }),
    );
    let _ = wait_response(&mut s.stdout, init);
    notify(&mut s.stdin, "initialized", serde_json::json!({}));
    let content = "§ T\n  x' : i32\n";
    notify(
        &mut s.stdin,
        "textDocument/didOpen",
        serde_json::json!({
            "textDocument": {
                "uri": "file:///test.csl",
                "languageId": "cslv3",
                "version": 1,
                "text": content,
            }
        }),
    );
    let cid = send(
        &mut s.stdin,
        "textDocument/completion",
        serde_json::json!({
            "textDocument": { "uri": "file:///test.csl" },
            "position": { "line": 1, "character": 4 },
            "context": {
                "triggerKind": 2,
                "triggerCharacter": "'"
            }
        }),
    );
    let resp = wait_response(&mut s.stdout, cid);
    let items = resp["result"].as_array().expect("completion array");
    // Expect the 9 morpheme tags.
    let labels: Vec<String> = items
        .iter()
        .filter_map(|v| v["label"].as_str().map(|s| s.to_string()))
        .collect();
    for tag in &["d", "f", "s", "t", "e", "m", "p", "g", "r"] {
        assert!(labels.iter().any(|l| l == *tag), "missing morpheme {tag} in {:?}", labels);
    }
    let sid = send(&mut s.stdin, "shutdown", serde_json::json!({}));
    let _ = wait_response(&mut s.stdout, sid);
    notify(&mut s.stdin, "exit", serde_json::json!({}));
}

#[test]
fn test_semantic_tokens_basic() {
    let mut s = start_server();
    let init = send(
        &mut s.stdin,
        "initialize",
        serde_json::json!({ "processId": null, "capabilities": {} }),
    );
    let _ = wait_response(&mut s.stdout, init);
    notify(&mut s.stdin, "initialized", serde_json::json!({}));
    let content = "# line comment\n§ T\n  x : i32 = 42\n";
    notify(
        &mut s.stdin,
        "textDocument/didOpen",
        serde_json::json!({
            "textDocument": {
                "uri": "file:///test.csl",
                "languageId": "cslv3",
                "version": 1,
                "text": content,
            }
        }),
    );
    let tid = send(
        &mut s.stdin,
        "textDocument/semanticTokens/full",
        serde_json::json!({ "textDocument": { "uri": "file:///test.csl" } }),
    );
    let resp = wait_response(&mut s.stdout, tid);
    let data = resp["result"]["data"].as_array().expect("data array");
    // Each token = 5 u32 entries ; at least comment + section + number exist.
    assert!(data.len() >= 10, "expected semantic tokens, got {:?}", data);
    let sid = send(&mut s.stdin, "shutdown", serde_json::json!({}));
    let _ = wait_response(&mut s.stdout, sid);
    notify(&mut s.stdin, "exit", serde_json::json!({}));
}
