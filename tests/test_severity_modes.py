#!/usr/bin/env python3
"""T14 — severity-mode CLI gate (Session-4)

Verifies the Q2/Q3 severity contract end-to-end by driving parser.exe with
each (mode × check) combination and asserting the exit code + emitted
severity label match the table from DECISIONS.md Session-3-close.

Matrix (checks × modes) — 6 checks × 3 sev-modes = 18 core assertions,
plus --strict-parse orthogonal axis = 4 extra = 22 total.

Mapping implemented here must stay in lockstep with
severity_for() in parser/semantic.odin.

Exit 0 if all assertions pass; 1 otherwise.
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"

# --- per-check fixtures that trip exactly one diagnostic kind ---
FIXTURES = {
    "clean":               "§ T\n  x : i32\n",
    "morph_dup":           "§ T\n  x.must.may : bool\n",
    "morph_order":         "§ T\n  x.cert.prog : bool\n",
    "morph_unknown":       "§ T\n  x.prog.fakebogus : bool\n",
    "evidence_contradict": "§ T\n  [x] a : i32\n  [!] a : i32\n",
    "permissive_anon_fn":  "§ T\n  fn () -> bool = true\n",
    "permissive_anon_def": "§ T\n  def = enum[ a, b ]\n",
}

# --- expected (severity-label, exit-code) per (fixture, flags) ---
# severity-label is what must appear in output ('error' | 'warn' | 'info' | '')
# exit-code is the expected process exit.
#
# mode-flag syntax: tuple of CLI args added beyond "--semantic".
EXPECT = {
    # clean : no diag, exit 0 in every mode
    ("clean",               ()                             ): ("",      0),
    ("clean",               ("--lint",)                    ): ("",      0),
    ("clean",               ("--strict",)                  ): ("",      0),
    ("clean",               ("--strict-parse",)            ): ("",      0),

    # dup-morph : always E (fails default + strict; lint mutes exit)
    ("morph_dup",           ()                             ): ("error", 1),
    ("morph_dup",           ("--lint",)                    ): ("error", 0),
    ("morph_dup",           ("--strict",)                  ): ("error", 1),

    # morph-order : W@default+lint, E@strict
    ("morph_order",         ()                             ): ("warn",  0),
    ("morph_order",         ("--lint",)                    ): ("warn",  0),
    ("morph_order",         ("--strict",)                  ): ("error", 1),

    # morph-unknown : W@default+lint, E@strict
    ("morph_unknown",       ()                             ): ("warn",  0),
    ("morph_unknown",       ("--lint",)                    ): ("warn",  0),
    ("morph_unknown",       ("--strict",)                  ): ("error", 1),

    # evidence-contradict : W always. --strict makes any W fail.
    ("evidence_contradict", ()                             ): ("warn",  0),
    ("evidence_contradict", ("--lint",)                    ): ("warn",  0),
    ("evidence_contradict", ("--strict",)                  ): ("warn",  1),

    # permissive anonymous fn : W@default+lint+strict, E@strict-parse
    ("permissive_anon_fn",  ()                             ): ("warn",  0),
    ("permissive_anon_fn",  ("--lint",)                    ): ("warn",  0),
    ("permissive_anon_fn",  ("--strict",)                  ): ("warn",  1),
    ("permissive_anon_fn",  ("--strict-parse",)            ): ("error", 1),
    ("permissive_anon_fn",  ("--strict", "--strict-parse") ): ("error", 1),

    # permissive anonymous enum : same shape as anon fn
    ("permissive_anon_def", ("--strict-parse",)            ): ("error", 1),
}


def run(path: Path, extra: tuple[str, ...]) -> tuple[int, str]:
    args = [str(PARSER), "--semantic", *extra, str(path)]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=15,
                          encoding="utf-8", errors="replace")
    return proc.returncode, (proc.stdout or "") + (proc.stderr or "")


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found.\n")
        return 2

    # write all fixtures once
    with tempfile.TemporaryDirectory(prefix="csl-sev-") as tmp:
        tmpdir = Path(tmp)
        paths: dict[str, Path] = {}
        for name, body in FIXTURES.items():
            p = tmpdir / f"{name}.csl"
            p.write_text(body, encoding="utf-8")
            paths[name] = p

        total = len(EXPECT)
        fails: list[str] = []

        for (fixture, flags), (want_label, want_rc) in EXPECT.items():
            rc, out = run(paths[fixture], flags)
            reasons: list[str] = []
            if rc != want_rc:
                reasons.append(f"rc={rc} want={want_rc}")
            if want_label:
                # look for `[<label>]` token in output
                needle = f"[{want_label}]"
                if needle not in out:
                    reasons.append(f"expected '{needle}' in output")
            else:
                # no diagnostic expected — reject if any diag label present
                if "[error]" in out or "[warn]" in out or "[info]" in out:
                    reasons.append("expected no diag, got one")
            if reasons:
                flag_str = " ".join(flags) or "(default)"
                fails.append(f"{fixture:<22} [{flag_str:<27}]  " + " ; ".join(reasons))

    print(f"severity-mode corpus : {total} assertions, {len(fails)} failures")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
