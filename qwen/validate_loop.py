#!/usr/bin/env python3
"""T25-adjacent — CSL3 ↔ Qwen3 round-trip validation loop.

Usage:
    python qwen/validate_loop.py "§ T\n  hp'd : i32\n"
    python qwen/validate_loop.py --file  my_prompt.txt
    python qwen/validate_loop.py --interactive

Flow:
    user-prompt
        ↓
    POST http://127.0.0.1:8080/v1/chat/completions
        (system : qwen/system_prompt.txt,
         user   : user-prompt)
        ↓
    Qwen response text
        ↓
    parser.exe cssllint --json  (validate any CSL3 blocks extracted)
        ↓
    if clean : print response
    if errors: feed diagnostics back to Qwen → retry (up to MAX_RETRIES)

Exit 0 on converged response ; 1 on persistent failures.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Iterable

import urllib.request
import urllib.error

ROOT       = Path(__file__).resolve().parent.parent
PARSER     = ROOT / "parser.exe"
SYS_PROMPT = ROOT / "qwen" / "system_prompt.txt"
ENDPOINT   = "http://127.0.0.1:8080/v1/chat/completions"
MAX_RETRIES = 3
TIMEOUT_SEC = 600   # long-context requests can take a while

FENCE_RE = re.compile(r"```(?:csl|cslv3|csl3)?\n(.*?)\n```", re.DOTALL)


def load_system_prompt() -> str:
    try:
        return SYS_PROMPT.read_text(encoding="utf-8")
    except FileNotFoundError:
        print(f"[fatal] {SYS_PROMPT} missing — run build_system_prompt.py first", file=sys.stderr)
        sys.exit(2)


def chat(messages: list[dict]) -> str:
    body = json.dumps({
        "model":    "qwen3-coder-next",
        "messages": messages,
        "temperature": 0.7,
        "top_p":    0.8,
        "max_tokens": 4096,
    }).encode("utf-8")
    req = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data["choices"][0]["message"]["content"]


def extract_csl_blocks(text: str) -> list[str]:
    """Extract fenced ```csl blocks (or whole text if no fences present).

    When the model produces naked CSLv3 (no fences), treat the whole response
    as one block. This is common when the system prompt is doing its job.
    """
    blocks = FENCE_RE.findall(text)
    if blocks:
        return blocks
    # Heuristic : if text starts with § or contains morpheme suffixes,
    # treat it as a single naked CSL3 block.
    if text.lstrip().startswith("§") or re.search(r"\w'[dfs temp gr]", text):
        return [text.strip()]
    return []


def run_cssllint(csl_text: str) -> dict:
    """Pipe a CSL3 block through parser.exe cssllint --json and return the JSON."""
    if not PARSER.exists():
        return {"status": "error", "msg": f"parser.exe missing at {PARSER}"}
    with tempfile.NamedTemporaryFile(
        "w", delete=False, suffix=".csl", encoding="utf-8"
    ) as f:
        f.write(csl_text)
        tmp = f.name
    try:
        rc = subprocess.run(
            [str(PARSER), "cssllint", "--json", tmp],
            capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=30,
        )
        try:
            return json.loads(rc.stdout)
        except json.JSONDecodeError:
            return {"status": "error",
                    "msg": f"cssllint non-JSON: {rc.stdout[:200]}",
                    "stderr": rc.stderr[:200]}
    finally:
        try:
            Path(tmp).unlink()
        except OSError:
            pass


def format_diag_feedback(lint: dict) -> str:
    diags = lint.get("diags", [])
    lines = [
        "Previous CSLv3 block had diagnostics from `parser.exe cssllint`:"
    ]
    for d in diags:
        lines.append(
            f"  line {d.get('line','?')} col {d.get('col','?')} "
            f"[{d.get('sev','?')}] {d.get('code','')} — {d.get('msg','')}"
        )
    lines.append("")
    lines.append(
        "Please re-emit the CSLv3 block fixing these diagnostics. "
        "Respect the 74-glyph master + morpheme grammar from the system prompt."
    )
    return "\n".join(lines)


def round_trip(user_prompt: str) -> int:
    sys_prompt = load_system_prompt()
    messages: list[dict] = [
        {"role": "system", "content": sys_prompt},
        {"role": "user",   "content": user_prompt},
    ]

    for attempt in range(1, MAX_RETRIES + 1):
        print(f"\n=== attempt {attempt}/{MAX_RETRIES} ===")
        t0 = time.time()
        try:
            reply = chat(messages)
        except urllib.error.URLError as e:
            print(f"[fatal] server unreachable at {ENDPOINT}: {e}", file=sys.stderr)
            print("hint: run qwen/serve_qwen3_coder_next.cmd first", file=sys.stderr)
            return 2
        dur = time.time() - t0
        print(f"[qwen reply in {dur:.1f}s, {len(reply)} chars]")
        print("─" * 60)
        print(reply)
        print("─" * 60)

        blocks = extract_csl_blocks(reply)
        if not blocks:
            print("[no CSLv3 blocks detected — response accepted as English prose]")
            return 0

        bad_blocks: list[tuple[int, dict]] = []
        for i, blk in enumerate(blocks):
            lint = run_cssllint(blk)
            status = lint.get("status", "?")
            counts = lint.get("counts", {})
            print(f"[block {i}] cssllint: status={status} counts={counts}")
            if status != "ok":
                bad_blocks.append((i, lint))

        if not bad_blocks:
            print("\n✓ all CSL3 blocks clean — converged")
            return 0

        # feed first bad block back
        feedback = format_diag_feedback(bad_blocks[0][1])
        messages.append({"role": "assistant", "content": reply})
        messages.append({"role": "user",      "content": feedback})
        print(f"\n[retrying with {len(bad_blocks)} bad block(s)]")

    print(f"\n✗ exceeded {MAX_RETRIES} retries — response did not converge",
          file=sys.stderr)
    return 1


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("prompt", nargs="?", help="user prompt (or use --file)")
    ap.add_argument("--file", type=Path, help="read prompt from file")
    ap.add_argument("--interactive", action="store_true",
                    help="loop on stdin forever")
    args = ap.parse_args()

    if args.interactive:
        print("CSL3 × Qwen3 validation loop. Ctrl-D to exit.")
        while True:
            try:
                line = input("\n>>> ")
            except (EOFError, KeyboardInterrupt):
                print("\n[bye]")
                return 0
            line = line.strip()
            if not line:
                continue
            round_trip(line)
        return 0

    if args.file:
        prompt = args.file.read_text(encoding="utf-8")
    elif args.prompt:
        prompt = args.prompt
    else:
        ap.error("supply a positional prompt, --file, or --interactive")
    return round_trip(prompt)


if __name__ == "__main__":
    sys.exit(main())
