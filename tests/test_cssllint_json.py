#!/usr/bin/env python3
"""T19 — cssllint subcommand + JSON schema validation (Session-4)

Invokes `parser cssllint --json <file>` on a mix of clean and bad fixtures,
parses the JSON output with stdlib json, and asserts the shape matches
the schema documented in specs/14_CSSLv3_BRIDGE.csl §§ LINT-PROTOCOL.

Schema :
  {
    "file":   str,
    "status": "ok" | "warn" | "error",
    "counts": { "info": int, "warn": int, "error": int },
    "diags":  [ { "line": int, "col": int, "sev": str, "code": str, "msg": str } ]
  }

Exit 0 on all green, 1 on any schema or exit-code violation.
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"

# Fixture, expected status, expected exit-code
CASES = [
    (ROOT / "examples" / "morpheme_stack_tutorial.csl", "ok",    0),
    (ROOT / "parser" / "tests" / "C6_slot_grammar.csl", "ok",    0),
    (ROOT / "parser" / "error_tests" / "i02_double_modality.csl", "error", 1),
    (ROOT / "parser" / "error_tests" / "m07_fn_no_name.csl",      "warn",  0),
    # With --strict-parse, m07 should become error + exit 1
    (ROOT / "parser" / "error_tests" / "m07_fn_no_name.csl",      "error", 1, ["--strict-parse"]),
]


REQUIRED_TOP_KEYS = {"file", "status", "counts", "diags"}
REQUIRED_COUNT_KEYS = {"info", "warn", "error"}
REQUIRED_DIAG_KEYS = {"line", "col", "sev", "code", "msg"}
VALID_STATUSES = {"ok", "warn", "error"}
VALID_SEVS = {"info", "warn", "error"}


def run(path: Path, extra: list[str]) -> tuple[int, str]:
    args = [str(PARSER), "cssllint", "--json", *extra, str(path)]
    proc = subprocess.run(args, capture_output=True, text=True, timeout=15,
                          encoding="utf-8", errors="replace")
    return proc.returncode, proc.stdout or ""


def validate_schema(data) -> list[str]:
    errs: list[str] = []
    if not isinstance(data, dict):
        return ["top-level not object"]
    missing = REQUIRED_TOP_KEYS - data.keys()
    if missing:
        errs.append(f"missing keys {missing}")
    if not isinstance(data.get("file"), str):
        errs.append("file not string")
    if data.get("status") not in VALID_STATUSES:
        errs.append(f"status not in {VALID_STATUSES}")
    counts = data.get("counts")
    if not isinstance(counts, dict) or REQUIRED_COUNT_KEYS - counts.keys():
        errs.append("counts malformed")
    diags = data.get("diags")
    if not isinstance(diags, list):
        errs.append("diags not list")
    else:
        for i, d in enumerate(diags):
            if not isinstance(d, dict) or REQUIRED_DIAG_KEYS - d.keys():
                errs.append(f"diag[{i}] missing keys")
                continue
            if not isinstance(d["line"], int) or not isinstance(d["col"], int):
                errs.append(f"diag[{i}] line/col not int")
            if d.get("sev") not in VALID_SEVS:
                errs.append(f"diag[{i}] sev invalid")
            if not d.get("code", "").startswith("CSL-"):
                errs.append(f"diag[{i}] code missing CSL- prefix")
    return errs


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found.\n")
        return 2

    fails: list[str] = []
    for rec in CASES:
        path = rec[0]
        want_status = rec[1]
        want_rc = rec[2]
        extra = rec[3] if len(rec) > 3 else []

        rc, out = run(path, extra)
        # parse JSON
        try:
            data = json.loads(out)
        except json.JSONDecodeError as e:
            fails.append(f"{path.name} {extra}: invalid JSON : {e}\n  out: {out!r}")
            continue
        # schema
        schema_errs = validate_schema(data)
        if schema_errs:
            fails.append(f"{path.name} {extra}: schema : {schema_errs}")
        # status
        if data.get("status") != want_status:
            fails.append(f"{path.name} {extra}: status={data.get('status')} want={want_status}")
        # exit code
        if rc != want_rc:
            fails.append(f"{path.name} {extra}: rc={rc} want={want_rc}")

    print(f"cssllint JSON : {len(CASES)} cases, {len(fails)} failures")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
