#!/usr/bin/env python3
"""T7 — parser performance benchmark

Generates synthetic CSL sources at token counts N ∈ {10², 10³, 10⁴, 10⁵}
and measures parse-time via parser.exe.

Target (task T7): N=10⁵ tokens ≤ 100 ms.

Token counts are approximate — we count tokens by regenerating the
benchmark source from a known template that averages ~8 tokens per line,
so N ≈ line_count × 8.

Output: table + pass/fail gate.

Exit 0 if all targets met; 1 otherwise.
"""

import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
BENCH_DIR = ROOT / "benchmarks"

# average tokens per stitched-block: measured ~ 8-10 tokens per line
# a block repeats cheap structured content to hit target token counts
BLOCK = """\
§ block_{i}
  def Row{i}'t ⟨
    id       : u32
    name     : str
    value    : f32 ⌈0..1⌉
    active   : bool
  ⟩
  fn handle{i} (r : &Row{i}'t) -> bool = true
  fn process{i} (r : &Row{i}'t, dt : f32) -> bool = true
  fn score{i} (r : &Row{i}'t) -> f32 = 0.0
"""

# tokens per block (measured with parser --tokens):
TOKENS_PER_BLOCK = 80     # rough average; used to size N


def generate(token_target: int) -> Path:
    BENCH_DIR.mkdir(exist_ok=True)
    blocks = max(1, token_target // TOKENS_PER_BLOCK)
    path = BENCH_DIR / f"bench_{token_target}.csl"
    with open(path, "w", encoding="utf-8") as f:
        for i in range(blocks):
            f.write(BLOCK.format(i=i))
    return path


def count_tokens(path: Path) -> int:
    proc = subprocess.run(
        [str(PARSER), "--tokens", str(path)],
        capture_output=True, text=True, timeout=60,
        encoding="utf-8", errors="replace",
    )
    # each token is one line in --tokens output (except EOF + error lines)
    lines = (proc.stdout or "").splitlines()
    return len(lines)


def time_parse(path: Path, runs: int = 3) -> tuple[float, float]:
    """Return (best_ms, mean_ms) over `runs` cold-start calls."""
    durations = []
    for _ in range(runs):
        t0 = time.perf_counter()
        proc = subprocess.run(
            [str(PARSER), "--errors", str(path)],
            capture_output=True, text=True, timeout=60,
        )
        durations.append(time.perf_counter() - t0)
        if proc.returncode not in (0, 1):  # 0=ok, 1=parse errors (we don't care)
            raise RuntimeError(f"parser died on {path}: rc={proc.returncode}")
    return min(durations) * 1000, sum(durations) * 1000 / runs


def main() -> int:
    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found.\n")
        return 2

    targets = [100, 1_000, 10_000, 100_000]
    target_100k_ms = 100  # task target
    rows = []

    for n in targets:
        path = generate(n)
        actual_tokens = count_tokens(path)
        best_ms, mean_ms = time_parse(path)
        rows.append((n, actual_tokens, best_ms, mean_ms, path.stat().st_size))

    # --- print table ---
    print(f"{'target':>10}  {'actual_tok':>10}  {'best_ms':>9}  {'mean_ms':>9}  "
          f"{'bytes':>9}  {'tok/ms':>9}")
    for n, tok, best, mean, size in rows:
        thru = tok / best if best > 0 else 0
        print(f"{n:>10,}  {tok:>10,}  {best:>9.1f}  {mean:>9.1f}  "
              f"{size:>9,}  {thru:>9,.0f}")

    # --- gate ---
    fails = []
    for n, tok, best, mean, _ in rows:
        if n == 100_000 and best > target_100k_ms:
            fails.append(f"N={n}: best {best:.1f}ms exceeds target {target_100k_ms}ms")

    if fails:
        for f in fails:
            print(f"  [FAIL] {f}", file=sys.stderr)
        return 1
    print(f"[OK] all targets met (10^5 tokens under {target_100k_ms} ms)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
