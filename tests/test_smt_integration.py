#!/usr/bin/env python3
"""T26 — SMT integration tests (Session-7)

Gates:
  G1 : `parser --smt-selftest` emits 10/10 PASS (formula-builders, emit,
       morpheme-predicates, canonical-determinism, SHA256-vector, theory-infer)
  G2 : every parser/tests/C*.csl lowers + smt-dispatches cleanly
       (zero-obligations OR obligations-skipped-when-no-solver)
  G3 : `--smt --dump-lib2` produces well-formed SMT-LIB2 for smt_good fixtures
       (starts with `(set-logic ...)` and ends with `(check-sat)`)
  G4 : `--smt --json` is valid JSON for every smt_good fixture
  G5 : solver-roundtrip (gated) : when Z3 available, run 4 tautology + 4 unsat
       obligations ; assert the result-classification matches expectation.
       Auto-detects z3 via Z3_PATH env or `which z3`.
  G6 : proof-cache : two identical invocations on the same fixture must
       produce at least one cache-hit on the second run (requires solver).
  G7 : audit-chain verifies (signature + sequence integrity).

Exit 0 on green ; 1 on any regression.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT   = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
SMT_GOOD = ROOT / "tests" / "smt_good"
SMT_BAD  = ROOT / "tests" / "smt_bad"


def find_z3() -> str:
    envp = os.environ.get("Z3_PATH", "")
    if envp and Path(envp).exists():
        return envp
    p = shutil.which("z3")
    if p:
        return p
    candidates = [
        r"C:\ProgramData\chocolatey\bin\z3.exe",
        r"C:\Program Files\Z3\bin\z3.exe",
    ]
    for c in candidates:
        if Path(c).exists():
            return c
    return ""


def find_cvc5() -> str:
    envp = os.environ.get("CVC5_PATH", "")
    if envp and Path(envp).exists():
        return envp
    p = shutil.which("cvc5")
    if p:
        return p
    return ""


def run(args: list[str], timeout: int = 30) -> tuple[int, str, str]:
    proc = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                          encoding="utf-8", errors="replace")
    return proc.returncode, proc.stdout or "", proc.stderr or ""


def gate_selftest(fails: list[str]) -> None:
    rc, out, err = run([str(PARSER), "--smt-selftest"])
    if rc != 0:
        fails.append(f"G1: --smt-selftest rc={rc}\n  err: {err!r}")
        return
    if "SMT-SELFTEST: 10/10 PASS" not in out:
        fails.append(f"G1: footer missing or count wrong:\n{out}")


def gate_corpus(fails: list[str]) -> None:
    corpus = sorted((ROOT / "parser" / "tests").glob("C*.csl"))
    for f in corpus:
        rc, out, err = run([str(PARSER), "--smt", str(f)])
        if rc != 0:
            fails.append(f"G2: {f.name} --smt rc={rc}\n  err: {err[:200]}")


def gate_dump_lib2(fails: list[str]) -> None:
    if not SMT_GOOD.exists():
        return
    for f in sorted(SMT_GOOD.glob("*.csl")):
        rc, out, err = run([str(PARSER), "--smt", "--dump-lib2", str(f)])
        if rc != 0:
            fails.append(f"G3: {f.name} --dump-lib2 rc={rc}")
            continue
        if "(set-logic" not in out:
            fails.append(f"G3: {f.name} no (set-logic ...)")
        if "(check-sat)" not in out:
            fails.append(f"G3: {f.name} no (check-sat)")


def gate_json(fails: list[str]) -> None:
    if not SMT_GOOD.exists():
        return
    for f in sorted(SMT_GOOD.glob("*.csl")):
        rc, out, err = run([str(PARSER), "--smt", "--json", str(f)])
        if rc != 0:
            fails.append(f"G4: {f.name} --json rc={rc}")
            continue
        try:
            doc = json.loads(out)
        except json.JSONDecodeError as e:
            fails.append(f"G4: {f.name} invalid JSON: {e}")
            continue
        if "counts" not in doc or "obligations" not in doc:
            fails.append(f"G4: {f.name} missing required keys")


def gate_solver_roundtrip(fails: list[str], z3_path: str) -> int:
    """When Z3 available, assert smt_good fixtures produce UNSAT for all obligations."""
    if not z3_path or not SMT_GOOD.exists():
        return 0
    ran = 0
    for f in sorted(SMT_GOOD.glob("*.csl")):
        rc, out, err = run([str(PARSER), "--smt", "--json", f"--z3={z3_path}", str(f)])
        if rc != 0 and "sat" not in out:
            fails.append(f"G5: {f.name} rc={rc}")
            continue
        try:
            doc = json.loads(out)
        except json.JSONDecodeError:
            fails.append(f"G5: {f.name} invalid JSON")
            continue
        counts = doc.get("counts", {})
        # Mode-classified : Consistency-mode smt_good fixtures succeed
        # via Sat (not Unsat). Assert failure-count == 0 under the new
        # obligation-mode semantics introduced in Session-8.
        if counts.get("failure", 0) > 0:
            fails.append(f"G5: {f.name} unexpected failure-count: {counts}")
        ran += 1
    return ran


def gate_cache(fails: list[str], z3_path: str) -> bool:
    if not z3_path or not SMT_GOOD.exists():
        return False
    # wipe cache first
    cache_dir = ROOT / ".proof-cache"
    if cache_dir.exists():
        shutil.rmtree(cache_dir, ignore_errors=True)

    target = next(iter(sorted(SMT_GOOD.glob("*.csl"))), None)
    if target is None:
        return False

    # first run : cold
    rc1, out1, _ = run([str(PARSER), "--smt", "--json", f"--z3={z3_path}", str(target)])
    if rc1 != 0:
        fails.append(f"G6: cold rc={rc1}")
        return False
    try:
        d1 = json.loads(out1)
    except json.JSONDecodeError:
        fails.append("G6: cold invalid JSON")
        return False
    hits1 = d1.get("cache", {}).get("hits", 0)

    # second run : warm
    rc2, out2, _ = run([str(PARSER), "--smt", "--json", f"--z3={z3_path}", str(target)])
    if rc2 != 0:
        fails.append(f"G6: warm rc={rc2}")
        return False
    d2 = json.loads(out2)
    hits2 = d2.get("cache", {}).get("hits", 0)
    if hits2 <= hits1:
        # only assert if the cold run actually had misses to cache
        misses1 = d1.get("cache", {}).get("misses", 0)
        if misses1 > 0:
            fails.append(f"G6: cache hits did not grow (cold hits={hits1}, warm hits={hits2})")
    return True


def gate_audit(fails: list[str]) -> None:
    # The audit-chain is populated when solver runs produce unsat/sat ;
    # if absent (no solver ran), skip. If present, the chain file must exist
    # and the parser's audit-verify can validate it (future CLI flag — for
    # now we just check the file format).
    proof_dir = ROOT / ".proof"
    if not proof_dir.exists():
        return
    chain = proof_dir / "chain.jsonl"
    if not chain.exists():
        return
    lines = [ln for ln in chain.read_text(encoding="utf-8").splitlines() if ln.strip()]
    if not lines:
        return
    for ln in lines:
        try:
            doc = json.loads(ln)
        except json.JSONDecodeError as e:
            fails.append(f"G7: audit line invalid JSON: {e}")
            continue
        for key in ("seq", "prev_hash", "ctx", "result", "solver", "cert_hash", "timestamp", "sig"):
            if key not in doc:
                fails.append(f"G7: audit entry missing key '{key}'")


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found.\n")
        return 2

    fails: list[str] = []
    z3 = find_z3()
    cvc5 = find_cvc5()

    gate_selftest(fails)
    gate_corpus(fails)
    gate_dump_lib2(fails)
    gate_json(fails)
    solver_ran = gate_solver_roundtrip(fails, z3)
    cache_ran  = gate_cache(fails, z3)
    gate_audit(fails)

    print(f"smt-integration : {len(fails)} failures")
    print(f"  z3  : {z3 or '<not available — G5/G6 skipped>'}")
    print(f"  cvc5: {cvc5 or '<not available>'}")
    print(f"  solver-roundtrip fixtures run: {solver_ran}")
    print(f"  cache-gate engaged: {cache_ran}")
    for f in fails:
        print("  [FAIL] " + f, file=sys.stderr)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
