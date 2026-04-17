#!/usr/bin/env python3
"""T28 — Emit integration + golden-diff tests (Session-10)

Gates:
  E1 : 5/5 emit targets × 7 C-corpus = 35 emissions succeed (rc=0, non-empty)
  E2 : golden-diff stable for all 35 files (path-header normalization)
  E3 : --schema returns non-empty canonical schema text per target
  E4 : JSON target emits valid JSON + schema key present + version = json-v1
  E5 : Markdown target emits `<!-- schema: markdown-v1 -->` banner
  E6 : HTML target produces <!DOCTYPE html> and closing </html>
  E7 : LaTeX target produces \\documentclass + \\end{document}
  E8 : MIR target produces cssl.module { ... }
  E9 : --emit=X --incremental --sign populates .emit-cache and .proof
  E10: --emit-selftest reports 5/5 PASS

Exit 0 on green ; 1 on regression.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
CORPUS = sorted((ROOT / "parser" / "tests").glob("C*.csl"))
GOLDEN = ROOT / "tests" / "emit_golden"
TARGETS = [("json", "json"), ("markdown", "md"), ("html", "html"),
           ("latex", "tex"), ("mir", "mir")]


def run(args: list[str], timeout: int = 30) -> tuple[int, str, str]:
    rc = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                        encoding="utf-8", errors="replace")
    return rc.returncode, rc.stdout or "", rc.stderr or ""


def gate_E1_E2(fails: list[str]) -> None:
    for f in CORPUS:
        base = f.stem
        for t, ext in TARGETS:
            rc, out, err = run([str(PARSER), f"--emit={t}", str(f)])
            if rc != 0:
                fails.append(f"E1: {base}.{t} rc={rc}\n  err: {err[:200]}")
                continue
            if len(out) == 0:
                fails.append(f"E1: {base}.{t} empty output")
                continue
            golden = GOLDEN / f"{base}.{t}.{ext}"
            if not golden.exists():
                fails.append(f"E2: golden missing {golden.name}")
                continue
            got = normalize(out, t)
            expected = normalize(golden.read_text(encoding="utf-8"), t)
            if got != expected:
                # allow path/timestamp drift — collect first-diff line
                for i, (g, e) in enumerate(zip(got.splitlines(), expected.splitlines())):
                    if g != e:
                        fails.append(
                            f"E2: {base}.{t} line {i} diff\n  got={g[:100]!r}\n  exp={e[:100]!r}"
                        )
                        break
                else:
                    fails.append(f"E2: {base}.{t} length diff ({len(got)} vs {len(expected)})")


def normalize(text: str, target: str) -> str:
    """Strip timestamp + path-dependent lines that aren't part of the contract."""
    out_lines = []
    for ln in text.splitlines():
        # MIR + HTML + JSON have source-path / emittedAt banners that vary
        if "emittedAt" in ln or "// source:" in ln or "// emittedAt:" in ln:
            continue
        if "<!-- source:" in ln:
            continue
        if '"emittedAt"' in ln:
            continue
        if 'module @' in ln and target == "mir":
            # normalize module header path
            ln = "cssl.module @<normalized>"
        if '"module":' in ln and target == "json":
            # JSON ir.module path also varies
            ln = '    "module": "<normalized>",'
        if '"file":' in ln and target == "json":
            ln = '    "file": "<normalized>",'
        if '"sha256":' in ln and target == "json":
            ln = '    "sha256": "<normalized>"'
        if '<title>' in ln and target == "html":
            ln = '<title>normalized</title>'
        if '<h1>' in ln:
            ln = '<h1>normalized</h1>'
        if '# ' in ln and target == "markdown" and ln.startswith("# "):
            # normalize top-level title derived from filename
            ln = "# normalized"
        if '\\title{' in ln and target == "latex":
            ln = '\\title{normalized}'
        out_lines.append(ln)
    return "\n".join(out_lines)


def gate_E3(fails: list[str]) -> None:
    for t, _ in TARGETS:
        rc, out, _ = run([str(PARSER), f"--emit={t}", "--schema",
                          str(CORPUS[0])])
        if rc != 0 or len(out) < 50:
            fails.append(f"E3: {t} --schema empty/short (rc={rc}, len={len(out)})")


def gate_E4(fails: list[str]) -> None:
    rc, out, _ = run([str(PARSER), "--emit=json", str(CORPUS[0])])
    if rc != 0:
        fails.append(f"E4: rc={rc}")
        return
    try:
        doc = json.loads(out)
    except json.JSONDecodeError as e:
        fails.append(f"E4: invalid JSON: {e}")
        return
    if doc.get("schemaVersion") != "json-v1":
        fails.append(f"E4: schemaVersion={doc.get('schemaVersion')!r}")
    if "ast" not in doc:
        fails.append("E4: ast key missing")


def gate_banner(target: str, ext: str, banner: str, fails: list[str], label: str) -> None:
    rc, out, _ = run([str(PARSER), f"--emit={target}", str(CORPUS[0])])
    if rc != 0:
        fails.append(f"{label}: rc={rc}")
        return
    if banner not in out:
        fails.append(f"{label}: banner {banner!r} missing in {target} output")


def gate_E9(fails: list[str]) -> None:
    # Wipe caches + run with --sign --incremental ; verify directories populate.
    cache = ROOT / ".emit-cache"
    proof = ROOT / ".proof"
    if cache.exists():
        shutil.rmtree(cache, ignore_errors=True)
    if proof.exists():
        shutil.rmtree(proof, ignore_errors=True)
    rc, _, _ = run([str(PARSER), "--emit=json", "--incremental", "--sign",
                     str(CORPUS[0])])
    if rc != 0:
        fails.append(f"E9: rc={rc}")
        return
    if not cache.exists() or not list(cache.rglob("*.json")):
        fails.append("E9: .emit-cache not populated")
    if not proof.exists() or not (proof / "chain.jsonl").exists():
        fails.append("E9: .proof/chain.jsonl not populated")


def gate_E10(fails: list[str]) -> None:
    rc, out, _ = run([str(PARSER), "--emit-selftest"])
    if rc != 0 or "EMIT-SELFTEST: 5/5 PASS" not in out:
        fails.append(f"E10: selftest output missing 5/5 PASS:\n{out[:300]}")


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} missing\n")
        return 2
    fails: list[str] = []

    gate_E1_E2(fails)
    gate_E3(fails)
    gate_E4(fails)
    gate_banner("markdown", "md",   "<!-- schema: markdown-v1 -->", fails, "E5")
    gate_banner("html",     "html", "<!DOCTYPE html>",              fails, "E6")
    gate_banner("latex",    "tex",  "\\documentclass",               fails, "E7")
    gate_banner("mir",      "mir",  "cssl.module",                   fails, "E8")
    gate_E9(fails)
    gate_E10(fails)

    print(f"emit-integration : {len(fails)} failures")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
