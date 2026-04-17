#!/usr/bin/env python3
"""T24 — LSP integration smoke-test (Session-9)

Gates:
  L1 : cslv3-lsp binary builds (cargo build)
  L2 : cargo test passes (Rust integration suite)
  L3 : initialize handshake via Python stdio client returns server capabilities
  L4 : textDocument/hover on `§` returns markdown with "section"
  L5 : textDocument/completion after `'` returns 9 morphemes
  L6 : textDocument/semanticTokens/full returns non-empty data array
  L7 : VSCode extension TypeScript compiles (tsc -p)

L1/L2/L7 are build gates — L3/L4/L5/L6 perform a real LSP handshake.
"""

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LSP_DIR = ROOT / "lsp"
SERVER_DIR = LSP_DIR / "server"
VSCODE_DIR = LSP_DIR / "editors" / "vscode"
LSP_BIN = LSP_DIR / "target" / "debug" / "cslv3-lsp.exe"
PARSER = ROOT / "parser.exe"


def run(cmd: list[str], cwd: Path | None = None, timeout: int = 120) -> tuple[int, str, str]:
    # On Windows, npm/npx are .cmd shims that need shell=True.
    use_shell = os.name == "nt" and cmd and cmd[0] in {"npm", "npx", "node", "tsc"}
    if use_shell:
        joined = " ".join(cmd)
        rc = subprocess.run(
            joined, capture_output=True, text=True, timeout=timeout, cwd=cwd,
            encoding="utf-8", errors="replace", shell=True,
        )
    else:
        rc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, cwd=cwd,
            encoding="utf-8", errors="replace",
        )
    return rc.returncode, rc.stdout or "", rc.stderr or ""


def gate_build(fails: list[str]) -> bool:
    if not shutil.which("cargo"):
        fails.append("L1: cargo not on PATH")
        return False
    rc, _, err = run(["cargo", "build"], cwd=LSP_DIR, timeout=600)
    if rc != 0:
        fails.append(f"L1: cargo build rc={rc}\n  err: {err[-500:]}")
        return False
    if not LSP_BIN.exists():
        fails.append(f"L1: {LSP_BIN} not present after build")
        return False
    return True


def gate_rust_tests(fails: list[str]) -> None:
    rc, out, err = run(
        ["cargo", "test", "--test", "integration", "--quiet"],
        cwd=LSP_DIR, timeout=300,
    )
    if rc != 0:
        fails.append(f"L2: cargo test rc={rc}\n  stdout: {out[-400:]}\n  stderr: {err[-400:]}")
        return
    # expect "4 passed"
    if "4 passed" not in out and "4 passed" not in err:
        fails.append(f"L2: expected 4 passed in cargo output:\n{out[-400:]}")


class LspClient:
    def __init__(self, proc):
        self.proc = proc
        self.next_id = 1

    def _send(self, obj):
        body = json.dumps(obj).encode("utf-8")
        header = f"Content-Length: {len(body)}\r\n\r\n".encode("ascii")
        self.proc.stdin.write(header)
        self.proc.stdin.write(body)
        self.proc.stdin.flush()

    def _recv(self):
        content_len = 0
        while True:
            line = self.proc.stdout.readline()
            if not line:
                raise RuntimeError("server closed stdout")
            line = line.decode("utf-8", errors="replace").rstrip()
            if line == "":
                break
            if line.lower().startswith("content-length:"):
                content_len = int(line.split(":", 1)[1].strip())
        body = self.proc.stdout.read(content_len)
        return json.loads(body.decode("utf-8"))

    def request(self, method, params):
        rid = self.next_id
        self.next_id += 1
        self._send({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        while True:
            resp = self._recv()
            if resp.get("id") == rid:
                return resp

    def notify(self, method, params):
        self._send({"jsonrpc": "2.0", "method": method, "params": params})


def gate_lsp_dance(fails: list[str]) -> None:
    if not LSP_BIN.exists() or not PARSER.exists():
        fails.append("L3: lsp bin or parser.exe missing")
        return
    proc = subprocess.Popen(
        [str(LSP_BIN), "--stdio", f"--parser-path={PARSER}"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    c = LspClient(proc)
    try:
        # L3 initialize
        r = c.request("initialize", {"processId": None, "capabilities": {}})
        caps = r.get("result", {}).get("capabilities", {})
        if "hoverProvider" not in caps:
            fails.append(f"L3: hoverProvider missing")
        if "completionProvider" not in caps:
            fails.append(f"L3: completionProvider missing")
        c.notify("initialized", {})

        # didOpen
        c.notify("textDocument/didOpen", {
            "textDocument": {
                "uri": "file:///smoke.csl",
                "languageId": "cslv3",
                "version": 1,
                "text": "§ T\n  x : i32 = 42\n",
            }
        })

        # L4 hover
        r = c.request("textDocument/hover", {
            "textDocument": {"uri": "file:///smoke.csl"},
            "position": {"line": 0, "character": 0},
        })
        val = ((r.get("result") or {}).get("contents") or {}).get("value", "")
        if "section" not in val.lower():
            fails.append(f"L4: hover missing 'section' markdown ({val!r})")

        # L5 completion after '
        c.notify("textDocument/didChange", {
            "textDocument": {"uri": "file:///smoke.csl", "version": 2},
            "contentChanges": [{"text": "§ T\n  x' : i32\n"}],
        })
        # brief pause to let didChange apply
        time.sleep(0.3)
        r = c.request("textDocument/completion", {
            "textDocument": {"uri": "file:///smoke.csl"},
            "position": {"line": 1, "character": 4},
            "context": {"triggerKind": 2, "triggerCharacter": "'"},
        })
        items = r.get("result") or []
        if isinstance(items, dict):
            items = items.get("items") or []
        labels = [it.get("label", "") for it in items]
        for tag in ["d", "f", "s", "t", "e", "m", "p", "g", "r"]:
            if tag not in labels:
                fails.append(f"L5: morpheme '{tag}' missing in completion ({labels})")
                break

        # L6 semantic tokens
        r = c.request("textDocument/semanticTokens/full", {
            "textDocument": {"uri": "file:///smoke.csl"},
        })
        data = ((r.get("result") or {}).get("data") or [])
        if len(data) < 5:
            fails.append(f"L6: semanticTokens data too short ({len(data)})")

        # Clean shutdown
        c.request("shutdown", {})
        c.notify("exit", {})
    finally:
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def gate_vscode_compile(fails: list[str]) -> None:
    # Skip if npm/node unavailable
    if not shutil.which("node"):
        fails.append("L7: node not on PATH")
        return
    if not (VSCODE_DIR / "node_modules").exists():
        rc, _, err = run(["npm", "install", "--no-audit", "--no-fund"], cwd=VSCODE_DIR, timeout=120)
        if rc != 0:
            fails.append(f"L7: npm install rc={rc}")
            return
    # Use npx to invoke local tsc
    rc, _, err = run(["npx", "tsc", "-p", "."], cwd=VSCODE_DIR, timeout=60)
    if rc != 0:
        fails.append(f"L7: tsc compile rc={rc}\n  err: {err[-400:]}")
        return
    if not (VSCODE_DIR / "out" / "extension.js").exists():
        fails.append("L7: out/extension.js missing after tsc")


def main() -> int:
    fails: list[str] = []

    # L1 build
    ok = gate_build(fails)
    if not ok:
        print(f"lsp-integration : {len(fails)} failures")
        for f in fails:
            print("  [FAIL] " + f, file=sys.stderr)
        return 1

    # L2 cargo test
    gate_rust_tests(fails)

    # L3/L4/L5/L6 full LSP dance
    gate_lsp_dance(fails)

    # L7 VSCode compile
    gate_vscode_compile(fails)

    print(f"lsp-integration : {len(fails)} failures")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
