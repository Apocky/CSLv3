#!/usr/bin/env python3
"""T16 — mutation-based round-trip fuzzer (Session-4)

Seeds : 20-ish clean fixtures (parser/tests/*.csl + examples/*.csl).
Strategy :
  Mutation per-seed with 50 random perturbations drawn from :
    - token-delete   (P=0.20)
    - token-insert   (P=0.20)
    - token-swap     (P=0.20)
    - glyph-substitute (P=0.20)  — swap ≤/≥/≠/→ variants
    - indent-perturb (P=0.10)
    - bracket-flip   (P=0.10)    — ⟨→{, [→(
Total ≥ 1000 executions, reproducible via seed.

Invariants checked (per Session-4 T16 spec):
  R1 : no crash          — parser must return a well-defined exit code
  R4 : no hang           — per-case 5s timeout
  R5 : rc ∈ {0, 1}       — never panic-127 or segfault

Budget : ≤ 60s on dev-hw, ≥ 1000 executions.

Findings log : tests/fuzz_findings.md — new shapes that caused R1/R4/R5 failure.

Exit 0 on green, 1 on any R-violation.
"""

import json
import os
import random
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARSER = ROOT / "parser.exe"
FINDINGS = ROOT / "tests" / "fuzz_findings.md"
TIME_BUDGET_S = 5.0
TOTAL_BUDGET_S = 60.0
TARGET_RUNS = 1000
MUTATIONS_PER_SEED = 50
DEFAULT_SEED = 20260416

# --- seed discovery ---
def discover_seeds() -> list[Path]:
    paths = []
    for d in ("parser/tests", "examples", "eval", "specs"):
        p = ROOT / d
        if p.is_dir():
            paths.extend(sorted(p.glob("*.csl")))
    return paths

# --- token-level operations ---
# We mutate at a granularity between character and line : whitespace-separated
# runs, preserving structure-critical glyphs.

TOKEN_RE = re.compile(r"\S+|\s+", re.UNICODE)

def tokenize(text: str) -> list[str]:
    return TOKEN_RE.findall(text)

def detokenize(tokens: list[str]) -> str:
    return "".join(tokens)

# --- glyph substitution table (equivalent-meaning variants) ---
GLYPH_SWAPS = {
    "→": "->",  "->": "→",
    "←": "<-",  "<-": "←",
    "⇒": "=>",  "=>": "⇒",
    "∀": "all", "all": "∀",
    "∃": "any", "any": "∃",
    "∈": "in",  "in": "∈",
    "≤": "<=",  "<=": "≤",
    "≥": ">=",  ">=": "≥",
    "≠": "!=",  "!=": "≠",
    "¬": "~",   "~": "¬",
    "∧": "&&",  "&&": "∧",
    "∨": "||",  "||": "∨",
}

BRACKET_FLIPS = {
    "⟨": "{",  "⟩": "}",
    "{": "⟨",  "}": "⟩",
    "[": "(",  "]": ")",
}

# --- mutators ---
def mut_token_delete(tokens: list[str], rng: random.Random) -> list[str]:
    if len(tokens) < 3:
        return tokens
    idx = rng.randrange(len(tokens))
    return tokens[:idx] + tokens[idx+1:]

def mut_token_insert(tokens: list[str], rng: random.Random) -> list[str]:
    pool = [".", ",", ";", ":", "=", "→", "⟨", "⟩", "§", "W!", "fn", "def", "let"]
    idx = rng.randrange(len(tokens) + 1)
    return tokens[:idx] + [rng.choice(pool), " "] + tokens[idx:]

def mut_token_swap(tokens: list[str], rng: random.Random) -> list[str]:
    if len(tokens) < 2:
        return tokens
    i = rng.randrange(len(tokens) - 1)
    out = tokens[:]
    out[i], out[i+1] = out[i+1], out[i]
    return out

def mut_glyph_substitute(tokens: list[str], rng: random.Random) -> list[str]:
    candidates = [i for i, t in enumerate(tokens) if t in GLYPH_SWAPS]
    if not candidates:
        return tokens
    i = rng.choice(candidates)
    out = tokens[:]
    out[i] = GLYPH_SWAPS[out[i]]
    return out

def mut_indent_perturb(tokens: list[str], rng: random.Random) -> list[str]:
    candidates = [i for i, t in enumerate(tokens) if "\n" in t]
    if not candidates:
        return tokens
    i = rng.choice(candidates)
    out = tokens[:]
    delta = rng.choice([-2, -1, 1, 2, 4])
    if delta > 0:
        out[i] = out[i] + " " * delta
    else:
        s = out[i]
        n = min(-delta, len(s) - s.count("\n"))
        # strip trailing spaces
        while n > 0 and s.endswith(" "):
            s = s[:-1]; n -= 1
        out[i] = s
    return out

def mut_bracket_flip(tokens: list[str], rng: random.Random) -> list[str]:
    candidates = [i for i, t in enumerate(tokens) if any(c in BRACKET_FLIPS for c in t)]
    if not candidates:
        return tokens
    i = rng.choice(candidates)
    out = tokens[:]
    out[i] = "".join(BRACKET_FLIPS.get(c, c) for c in out[i])
    return out

MUTATORS = [
    (mut_token_delete,     20),
    (mut_token_insert,     20),
    (mut_token_swap,       20),
    (mut_glyph_substitute, 20),
    (mut_indent_perturb,   10),
    (mut_bracket_flip,     10),
]

def apply_random_mutation(tokens: list[str], rng: random.Random) -> list[str]:
    weights = [w for _, w in MUTATORS]
    mut = rng.choices([m for m, _ in MUTATORS], weights=weights, k=1)[0]
    return mut(tokens, rng)

def run_parser(content: bytes) -> tuple[int, float, str]:
    """Pipe content to a temp file and invoke parser.exe --errors."""
    import tempfile
    with tempfile.NamedTemporaryFile(mode="wb", suffix=".csl", delete=False) as f:
        f.write(content)
        tmp = f.name
    try:
        t0 = time.perf_counter()
        try:
            proc = subprocess.run(
                [str(PARSER), "--errors", tmp],
                capture_output=True, timeout=TIME_BUDGET_S,
            )
        except subprocess.TimeoutExpired:
            return -1, TIME_BUDGET_S, "TIMEOUT"
        elapsed = time.perf_counter() - t0
        return proc.returncode, elapsed, (proc.stderr or b"").decode("utf-8", errors="replace")[:400]
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def main() -> int:
    seed = int(os.environ.get("FUZZ_SEED", DEFAULT_SEED))
    if len(sys.argv) > 1 and sys.argv[1].isdigit():
        seed = int(sys.argv[1])
    rng = random.Random(seed)

    if not PARSER.exists():
        sys.stderr.write(f"ERROR: {PARSER} not found.\n")
        return 2

    seeds = discover_seeds()
    if not seeds:
        sys.stderr.write("ERROR: no seed fixtures found.\n")
        return 2

    findings: list[dict] = []
    total_runs = 0
    hangs = 0
    crashes = 0
    total_elapsed = 0.0
    t_start = time.perf_counter()

    for seed_path in seeds:
        try:
            seed_text = seed_path.read_text(encoding="utf-8")
        except OSError:
            continue
        tokens = tokenize(seed_text)
        for mut_i in range(MUTATIONS_PER_SEED):
            if time.perf_counter() - t_start > TOTAL_BUDGET_S:
                break
            if total_runs >= TARGET_RUNS * 3:  # hard upper bound
                break
            # apply 1-3 mutations
            nmuts = rng.choice([1, 1, 2, 3])
            mutated = tokens[:]
            for _ in range(nmuts):
                mutated = apply_random_mutation(mutated, rng)
            content = detokenize(mutated).encode("utf-8", errors="replace")
            rc, elapsed, stderr = run_parser(content)
            total_runs += 1
            total_elapsed += max(elapsed, 0.0)
            # R1/R4/R5 checks
            if rc == -1:
                hangs += 1
                findings.append({
                    "kind": "hang", "seed": seed_path.name, "mut_i": mut_i,
                    "content_head": content[:200].decode("utf-8", errors="replace"),
                    "stderr": stderr,
                })
            elif rc not in (0, 1):
                crashes += 1
                findings.append({
                    "kind": "crash", "rc": rc, "seed": seed_path.name, "mut_i": mut_i,
                    "content_head": content[:200].decode("utf-8", errors="replace"),
                    "stderr": stderr,
                })
        if time.perf_counter() - t_start > TOTAL_BUDGET_S:
            break

    wall = time.perf_counter() - t_start
    per_case_ms = (total_elapsed * 1000.0) / max(total_runs, 1)
    throughput = total_runs / wall if wall > 0 else 0.0

    print(f"fuzz : seed={seed}  runs={total_runs}  hangs={hangs}  crashes={crashes}  "
          f"wall={wall:.1f}s  per-case={per_case_ms:.1f}ms  tp={throughput:.0f}/s")

    # Write findings log (overwrites on each run with latest cohort)
    FINDINGS.parent.mkdir(parents=True, exist_ok=True)
    with open(FINDINGS, "w", encoding="utf-8") as f:
        f.write("# T16 fuzz-roundtrip findings\n\n")
        f.write(f"seed = {seed}  runs = {total_runs}  hangs = {hangs}  crashes = {crashes}  "
                f"wall = {wall:.1f}s  throughput = {throughput:.0f}/s\n\n")
        if not findings:
            f.write("✓ no R1/R4/R5 violations detected in this run.\n")
        else:
            f.write(f"## {len(findings)} findings\n\n")
            for i, rec in enumerate(findings[:50]):  # cap log size
                f.write(f"### finding {i+1} : {rec['kind']} (seed {rec['seed']}, mut {rec['mut_i']})\n\n")
                f.write("```\n")
                f.write(rec.get("content_head", ""))
                f.write("\n```\n")
                if rec.get("stderr"):
                    f.write("stderr:\n```\n")
                    f.write(rec["stderr"])
                    f.write("\n```\n")
                f.write("\n")

    # Gate : R1, R4, R5
    fails = []
    if hangs > 0:
        fails.append(f"R4 : {hangs} hangs (expected 0)")
    if crashes > 0:
        fails.append(f"R1/R5 : {crashes} crashes (expected 0)")
    if total_runs < TARGET_RUNS:
        fails.append(f"budget : {total_runs} runs (expected >= {TARGET_RUNS})")
    if wall > TOTAL_BUDGET_S + 5:
        fails.append(f"budget : {wall:.1f}s (expected <= {TOTAL_BUDGET_S}s)")

    if fails:
        for f in fails:
            print("  [FAIL] " + f, file=sys.stderr)
        return 1
    print(f"  all gates green ; findings logged to {FINDINGS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
