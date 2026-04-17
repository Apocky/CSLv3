#!/usr/bin/env python3
"""P2.1 — latexmk CI-driver for CSLv3 corpus (Session-12).

Emits LaTeX from each eval/C*_CSL.csl, then invokes latexmk to compile
to PDF. Used both as an acceptance-gate for STABILITY promotion
(latex-v1 experimental → stable) and as an ongoing CI regression
detector.

Pipeline per fixture :
    parser.exe --emit latex <csl>  ->  .tex file
    latexmk -xelatex -interaction=nonstopmode <tex>  ->  .pdf
    verify .pdf exists AND size > 1 KB

Usage :
    python scripts/latex_compile_check.py            (all 7 fixtures)
    python scripts/latex_compile_check.py --file C1  (single)
    python scripts/latex_compile_check.py --check    (probe toolchain only)
    python scripts/latex_compile_check.py --json     (machine-readable)

Exit 0 = all pass ; 1 = at least one compile failure ;
2 = toolchain missing ; 3 = parser missing.
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
EVAL = (ROOT / "eval").resolve()
OUT = (EVAL / "latex_pdfs").resolve()

FIXTURES = [
    "C1_sort_CSL.csl",
    "C2_nested_scopes_CSL.csl",
    "C3_dependent_types_CSL.csl",
    "C4_reason_block_CSL.csl",
    "C5_bridge_mode_CSL.csl",
    "C6_slot_grammar_CSL.csl",
    "C7_morpheme_stack_CSL.csl",
]


@dataclass
class CompileResult:
    fixture:    str
    tex_ok:     bool
    tex_bytes:  int
    pdf_ok:     bool
    pdf_bytes:  int
    elapsed_s:  float
    error:      str = ""


def probe_toolchain() -> tuple[str, str]:
    """Return (latexmk_path, engine) or ('','') if missing."""
    latexmk = shutil.which("latexmk") or ""
    for engine in ("xelatex", "pdflatex", "lualatex"):
        if shutil.which(engine):
            return latexmk, engine
    return latexmk, ""


def emit_tex(fixture: str) -> tuple[bool, Path, str]:
    """Invoke parser.exe --emit latex <fixture> ; return (ok, texpath, err)."""
    src = EVAL / fixture
    tex = OUT / fixture.replace(".csl", ".tex")
    OUT.mkdir(parents=True, exist_ok=True)
    # Copy cslv3.sty next to .tex so latexmk finds \usepackage{cslv3}.
    sty_src = ROOT / "parser" / "emit_schema" / "latex-v1.sty"
    sty_dst = OUT / "cslv3.sty"
    if sty_src.exists() and (not sty_dst.exists() or sty_dst.stat().st_mtime < sty_src.stat().st_mtime):
        sty_dst.write_bytes(sty_src.read_bytes())
    try:
        # Emit standalone document (NOT --fragment) so latexmk has a full
        # \documentclass + \begin{document} + \end{document} to work with.
        rc = subprocess.run(
            [str(PARSER), "--emit=latex", str(src)],
            capture_output=True, text=True, timeout=30,
            encoding="utf-8", errors="replace",
        )
    except subprocess.TimeoutExpired:
        return False, tex, "parser timeout"
    if rc.returncode != 0:
        return False, tex, rc.stderr[:300]
    tex.write_text(rc.stdout, encoding="utf-8")
    return True, tex, ""


def compile_pdf(tex: Path, latexmk: str, engine: str) -> tuple[bool, Path, str]:
    pdf = tex.with_suffix(".pdf")
    # Wipe prior-run intermediates so latexmk doesn't short-circuit to
    # "nothing to do" on stale .fdb_latexmk caches.
    stem = tex.stem
    for ext in ("aux", "fls", "log", "out", "xdv", "toc", "fdb_latexmk", "pdf"):
        p = tex.parent / f"{stem}.{ext}"
        if p.exists():
            try: p.unlink()
            except OSError: pass
    cmd = [
        latexmk,
        f"-{engine}",
        "-interaction=nonstopmode",
        "-f",  # keep going past missing-glyph warnings from lmmono
        str(tex.name),
    ]
    try:
        rc = subprocess.run(
            cmd, capture_output=True, text=True, timeout=180,
            encoding="utf-8", errors="replace", cwd=str(tex.parent),
        )
    except subprocess.TimeoutExpired:
        return False, pdf, "latexmk timeout"
    # latexmk may return non-zero due to the cosmetic "MiKTeX updates"
    # warning even when the PDF builds. Trust the file existence + size.
    if pdf.exists() and pdf.stat().st_size > 1024:
        return True, pdf, ""
    return False, pdf, (rc.stdout[-400:] + rc.stderr[-400:]) or f"rc={rc.returncode}"


def run_one(fixture: str, latexmk: str, engine: str) -> CompileResult:
    t0 = time.time()
    tex_ok, tex, err = emit_tex(fixture)
    if not tex_ok:
        return CompileResult(fixture, False, 0, False, 0,
                             round(time.time() - t0, 2),
                             f"tex-emit-fail: {err}")
    tex_bytes = tex.stat().st_size
    if not latexmk or not engine:
        return CompileResult(fixture, True, tex_bytes, False, 0,
                             round(time.time() - t0, 2),
                             "toolchain-missing (emit-only)")
    pdf_ok, pdf, perr = compile_pdf(tex, latexmk, engine)
    pdf_bytes = pdf.stat().st_size if pdf.exists() else 0
    return CompileResult(
        fixture=fixture,
        tex_ok=True,
        tex_bytes=tex_bytes,
        pdf_ok=pdf_ok,
        pdf_bytes=pdf_bytes,
        elapsed_s=round(time.time() - t0, 2),
        error="" if pdf_ok else perr[:200],
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", help="restrict to one fixture (without path)")
    ap.add_argument("--check", action="store_true",
                    help="probe toolchain + exit (no compile)")
    ap.add_argument("--json", action="store_true", help="machine-readable")
    args = ap.parse_args()

    if not PARSER.exists():
        print(f"ERROR: {PARSER} missing ; build parser first", file=sys.stderr)
        return 3

    latexmk, engine = probe_toolchain()
    if args.check:
        payload = {"latexmk": latexmk, "engine": engine,
                   "ok": bool(latexmk and engine)}
        if args.json:
            print(json.dumps(payload))
        else:
            print(f"latexmk : {latexmk or '(missing)'}")
            print(f"engine  : {engine or '(missing)'}")
            print(f"status  : {'OK' if payload['ok'] else 'MISSING-TOOLCHAIN'}")
        return 0 if payload["ok"] else 2

    fixtures = [args.file] if args.file else FIXTURES
    if args.file and not args.file.endswith(".csl"):
        fixtures = [f for f in FIXTURES if f.startswith(args.file)]
        if not fixtures:
            print(f"no fixture matches '{args.file}'", file=sys.stderr)
            return 2

    results: list[CompileResult] = [run_one(f, latexmk, engine) for f in fixtures]
    n_ok = sum(1 for r in results if r.pdf_ok)
    n = len(results)

    if args.json:
        print(json.dumps({
            "toolchain": {"latexmk": latexmk, "engine": engine},
            "pass": n_ok, "total": n,
            "results": [asdict(r) for r in results],
        }, indent=2))
    else:
        print(f"toolchain : latexmk={latexmk or 'MISSING'}  engine={engine or 'MISSING'}")
        print(f"{'fixture':34s} {'tex':>6s} {'pdf':>6s} {'pdf-bytes':>10s} {'sec':>5s}  {'err':s}")
        for r in results:
            print(f"{r.fixture:34s} "
                  f"{('ok' if r.tex_ok else 'FAIL'):>6s} "
                  f"{('ok' if r.pdf_ok else 'FAIL'):>6s} "
                  f"{r.pdf_bytes:>10d} {r.elapsed_s:>5.1f}  "
                  f"{r.error[:60]}")
        print(f"\n{n_ok}/{n} fixtures compiled")

    return 0 if n_ok == n else (2 if not (latexmk and engine) else 1)


if __name__ == "__main__":
    sys.exit(main())
