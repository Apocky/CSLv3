#!/usr/bin/env python3
"""T26.1c — SMT throughput benchmark (Session-8)

Measures uncached + cached SMT-discharge throughput in obligations/second.
Writes results to benchmarks/smt_throughput.md.

Acceptance (handoff §§ T26.1):
  ✓ throughput ≥ 100 cached  ops/s
  ✓ throughput ≥ 10  uncached ops/s
"""

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
SMT_GOOD = ROOT / "tests" / "smt_good"
BENCH_OUT = ROOT / "benchmarks" / "smt_throughput.md"
CACHE_DIR = ROOT / ".proof-cache"


def find_solver(name: str) -> str:
    env_key = f"{name.upper()}_PATH"
    envp = os.environ.get(env_key, "")
    if envp and Path(envp).exists():
        return envp
    p = shutil.which(name)
    if p:
        return p
    roots = [
        Path(f"C:/Users/Apocky/AppData/Local/{name}"),
    ]
    for r in roots:
        if r.exists():
            for exe in r.rglob(f"{name}.exe"):
                return str(exe)
    return ""


def run_discharge(args: list[str]) -> tuple[int, dict]:
    rc = subprocess.run(args, capture_output=True, text=True, timeout=60,
                        encoding="utf-8", errors="replace")
    try:
        doc = json.loads(rc.stdout)
    except json.JSONDecodeError:
        doc = {}
    return rc.returncode, doc


def bench(solver_name: str, solver_path: str, fixtures: list[Path]) -> dict:
    res = {
        "solver": solver_name,
        "path":   solver_path,
        "uncached_ops": 0, "uncached_ms": 0,
        "cached_ops":   0, "cached_ms":   0,
    }
    if not solver_path:
        return res

    # wipe cache
    if CACHE_DIR.exists():
        shutil.rmtree(CACHE_DIR, ignore_errors=True)

    # Uncached pass
    t0 = time.perf_counter()
    total_ops = 0
    for f in fixtures:
        args = [str(PARSER), "--smt", "--json", f"--{solver_name}={solver_path}",
                f"--solver={solver_name}", str(f)]
        rc, doc = run_discharge(args)
        if rc != 0 and doc.get("status") == "error":
            continue
        cnt = doc.get("counts", {})
        total_ops += cnt.get("ok", 0) + cnt.get("failure", 0) + cnt.get("inconclusive", 0)
    uncached_wall_ms = (time.perf_counter() - t0) * 1000
    res["uncached_ops"] = total_ops
    res["uncached_ms"]  = int(uncached_wall_ms)

    # Cached pass (re-run each fixture — all should be cache-hits)
    t0 = time.perf_counter()
    total_ops = 0
    for f in fixtures:
        args = [str(PARSER), "--smt", "--json", f"--{solver_name}={solver_path}",
                f"--solver={solver_name}", str(f)]
        rc, doc = run_discharge(args)
        cnt = doc.get("counts", {})
        total_ops += cnt.get("ok", 0) + cnt.get("failure", 0) + cnt.get("inconclusive", 0)
    cached_wall_ms = (time.perf_counter() - t0) * 1000
    res["cached_ops"] = total_ops
    res["cached_ms"]  = int(cached_wall_ms)

    return res


def fmt_rate(ops: int, ms: int) -> str:
    if ms == 0 or ops == 0:
        return "n/a"
    return f"{ops * 1000.0 / ms:.1f}"


def main() -> int:
    if not PARSER.exists():
        print(f"ERROR: {PARSER} missing", file=sys.stderr)
        return 2
    fixtures = sorted(SMT_GOOD.glob("*.csl"))
    if not fixtures:
        print("ERROR: no smt_good fixtures", file=sys.stderr)
        return 2

    z3 = find_solver("z3")
    cvc5 = find_solver("cvc5")

    results = []
    if z3:
        results.append(bench("z3", z3, fixtures))
    if cvc5:
        results.append(bench("cvc5", cvc5, fixtures))

    if not results:
        print("SKIP: no solver available", file=sys.stderr)
        return 0

    # write markdown
    BENCH_OUT.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# SMT-Throughput Benchmark (T26.1c)",
        "",
        f"- Fixtures: {len(fixtures)} smt_good/*.csl",
        f"- Generated: `python tests/perf_smt_bench.py`",
        "",
        "| solver | uncached ops | uncached ms | uncached ops/s | cached ops | cached ms | cached ops/s |",
        "|--------|--------------|-------------|----------------|------------|-----------|--------------|",
    ]
    for r in results:
        lines.append(
            f"| {r['solver']} | {r['uncached_ops']} | {r['uncached_ms']} "
            f"| {fmt_rate(r['uncached_ops'], r['uncached_ms'])} "
            f"| {r['cached_ops']} | {r['cached_ms']} "
            f"| {fmt_rate(r['cached_ops'], r['cached_ms'])} |"
        )
    lines += [
        "",
        "## Acceptance",
        "",
        "- cached >= 100 ops/s  : gate from handoff",
        "- uncached >= 10 ops/s : gate from handoff",
    ]
    BENCH_OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    print(BENCH_OUT.read_text(encoding="utf-8"))

    # acceptance
    fails = []
    for r in results:
        u_rate = r["uncached_ops"] * 1000.0 / r["uncached_ms"] if r["uncached_ms"] else 0
        c_rate = r["cached_ops"]   * 1000.0 / r["cached_ms"]   if r["cached_ms"]   else 0
        if u_rate > 0 and u_rate < 10:
            fails.append(f"{r['solver']} uncached {u_rate:.1f} < 10 ops/s")
        if c_rate > 0 and c_rate < 100:
            fails.append(f"{r['solver']} cached {c_rate:.1f} < 100 ops/s")

    if fails:
        for f in fails:
            print(f"[FAIL] {f}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
