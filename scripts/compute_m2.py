#!/usr/bin/env python3
"""T25.2 — m₂ perplexity metric harness (Session-11).

Definition:
  m₂ ≡ (NLL_csl / |csl_tokens|) / (NLL_en / |en_tokens|)
  where NLL is negative-log-likelihood under a fixed model.
  m₂ < 1.0 : CSL more-predictable than EN (unlikely due to rare glyphs)
  m₂ ≈ 1.0 : equal density
  m₂ ≤ 1.2 : target (CSL ≤ 1.2× EN perplexity)
  m₂ > 1.5 : CSL too-surprising ; model unfamiliar with notation

Multi-model usage reduces single-model bias. Bootstrap CI gives
non-parametric confidence intervals (standard 1000 resamples).

CLI:
  python scripts/compute_m2.py <csl-file>                    → all models
  python scripts/compute_m2.py <csl-file> --model=small       → one model
  python scripts/compute_m2.py --all-eval                    → full corpus
  python scripts/compute_m2.py <csl-file> --json             → machine-readable
  python scripts/compute_m2.py <csl-file> --token-nll        → per-token output
  python scripts/compute_m2.py --self-test                   → mock-model smoke

Backends:
  real   : llama-cpp-python + GGUF checkpoint (preferred)
  mock   : deterministic pseudo-NLL (tokenizer proxy) for CI / tests
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import random
import re
import sys
import time
from dataclasses import dataclass, asdict, field
from pathlib import Path
from typing import Any, Iterable

# Local imports ; tolerate sibling-script layout
SCRIPT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPT_DIR))
import m2_models  # noqa: E402

ROOT       = SCRIPT_DIR.parent
EVAL_DIR   = ROOT / "eval"
PARA_DIR   = EVAL_DIR / "paraphrases"
RESULTS    = EVAL_DIR / "m2_results"
CACHE_DIR  = ROOT / ".m2-cache"
BASELINE   = EVAL_DIR / "m2_baseline.json"

BOOTSTRAP_DEFAULT = 1000
SEED_DEFAULT      = 20260417

# Map CSL file → paraphrase ; adjust when paraphrases land
CSL_TO_PARAPHRASE = {
    "C1_sort":           "C1",
    "C2_nested_scopes":  "C2",
    "C3_dependent_types":"C3",
    "C4_reason_block":   "C4",
    "C5_bridge_mode":    "C5",
    "C6_slot_grammar":   "C6",
    "C7_morpheme_stack": "C7",
}


# ---------- Result types ----------

@dataclass
class TokenNLL:
    token_id:   int
    token_str:  str
    nll:        float

@dataclass
class Measurement:
    file:               str
    paraphrase:         str
    model_key:          str
    model_name:         str
    model_sha:          str
    csl_n_tokens:       int
    en_n_tokens:        int
    csl_mean_nll:       float
    en_mean_nll:        float
    m2:                 float
    m2_ci_low:          float
    m2_ci_high:         float
    bootstrap_n:        int
    seed:               int
    elapsed_sec:        float
    backend:            str           # "real" | "mock"
    csl_token_nll:      list[TokenNLL] = field(default_factory=list)
    en_token_nll:       list[TokenNLL] = field(default_factory=list)

    def compact(self) -> dict:
        """Dict with metadata only — strip per-token lists (large)."""
        d = asdict(self)
        d["csl_token_nll"] = f"[{len(self.csl_token_nll)} tokens]"
        d["en_token_nll"]  = f"[{len(self.en_token_nll)} tokens]"
        return d


# ---------- Backend : llama-cpp-python (real) ----------

class RealBackend:
    def __init__(self, spec: m2_models.ModelSpec):
        try:
            from llama_cpp import Llama
        except ImportError as e:
            raise RuntimeError(
                "llama-cpp-python not installed. "
                "Run `pip install llama-cpp-python` or use --backend=mock."
            ) from e
        path = spec.cached_path
        if not path.exists():
            raise FileNotFoundError(
                f"{spec.name} GGUF not at {path}. Run scripts/m2_install_models.sh."
            )
        print(f"[real] loading {spec.name} from {path.name} ...", file=sys.stderr)
        t0 = time.time()
        self.llm = Llama(
            model_path=str(path),
            n_ctx=min(spec.context, 8192),
            n_threads=None,
            n_gpu_layers=0,          # CPU-only by default for reproducibility
            logits_all=True,
            verbose=False,
            seed=SEED_DEFAULT,
        )
        self.spec = spec
        self.sha = m2_models.sha256_of_file(path) if path.exists() else "UNSET"
        print(f"[real] loaded in {time.time()-t0:.1f}s", file=sys.stderr)

    def token_nll(self, text: str) -> list[TokenNLL]:
        """Teacher-forced per-token NLL for `text` (list[TokenNLL])."""
        import numpy as np
        tokens = self.llm.tokenize(text.encode("utf-8"))
        if len(tokens) < 2:
            return []
        self.llm.reset()
        out: list[TokenNLL] = []
        # Evaluate prefix (n-1 tokens) then we have logits for predicting tokens[1..]
        self.llm.eval(tokens[:-1])
        logits = np.asarray(self.llm.scores[: len(tokens) - 1])
        # Convert logits → log-probs via stable log-softmax row-wise
        max_l = logits.max(axis=1, keepdims=True)
        stab = logits - max_l
        logsumexp = np.log(np.exp(stab).sum(axis=1, keepdims=True))
        log_probs = stab - logsumexp
        for i, tok in enumerate(tokens[1:]):
            lp = float(log_probs[i, tok])
            tok_str = self.llm.detokenize([tok]).decode("utf-8", "replace")
            out.append(TokenNLL(token_id=tok, token_str=tok_str, nll=-lp))
        return out


# ---------- Backend : mock (deterministic, no model) ----------

class MockBackend:
    """Deterministic pseudo-NLL backend for CI + unit tests.

    Mock NLL per character :
      - ASCII alnum/space/punct       → 2.0  (common, low surprise)
      - Unicode > U+07FF              → 5.0  (multi-byte glyph, high)
      - apostrophe / morpheme markers → 3.5
      - typical CSL structural glyphs → 4.0 (§ ¶ → ← ≤ ≥ ⊗ etc.)
    NLL summed + mean-reduced per mock-token (which equals ~4-char group).
    This produces a consistent, reproducible metric suitable for smoke-
    testing harness plumbing without real-model weights.
    """

    TOKEN_GROUP = 4   # ~4-char "tokens"

    def __init__(self, spec: m2_models.ModelSpec):
        self.spec = spec
        self.sha = hashlib.sha256(
            f"mock:{spec.key}:v1".encode()
        ).hexdigest()

    @staticmethod
    def _char_nll(c: str) -> float:
        if not c:
            return 0.0
        cp = ord(c)
        if cp > 0x07FF:
            return 5.0                    # multi-byte glyph
        if c == "'":
            return 3.5                    # morpheme marker
        if c in "§¶→←↔≤≥⊗⊕":                # common CSL structural (<0x7FF but distinctive)
            return 4.0
        if c.isalnum() or c.isspace() or c in ".,:;()[]{}":
            return 2.0
        return 3.0

    def token_nll(self, text: str) -> list[TokenNLL]:
        out: list[TokenNLL] = []
        i = 0
        while i < len(text):
            chunk = text[i : i + self.TOKEN_GROUP]
            nll = sum(self._char_nll(c) for c in chunk)
            out.append(TokenNLL(
                token_id=hash(chunk) & 0xFFFFFFFF,
                token_str=chunk,
                nll=nll,
            ))
            i += self.TOKEN_GROUP
        return out


# ---------- Helpers ----------

def load_backend(spec: m2_models.ModelSpec, kind: str) -> Any:
    if kind == "mock":
        return MockBackend(spec)
    if kind == "real":
        return RealBackend(spec)
    if kind == "cli":
        return CliBackend(spec)
    raise ValueError(f"unknown backend: {kind}")


# ---------- Backend : llama-perplexity.exe subprocess (cli) ----------
# Uses the pre-built llama-perplexity.exe from D:/llama.cpp/ (Session-11
# Qwen3 bootstrap). Runs in CHUNK mode : small ctx-size (64) + repeat-
# padding the input text until >= 2*ctx tokens, producing per-chunk
# perplexities. Each chunk's log(PPL) is treated as one NLL sample for
# bootstrap CI.
#
# Why this approach (not /v1/completions echo, not llama-cpp-python) :
#   - llama-cpp-python : requires MSVC + ~10min source build on Py3.14
#   - llama-server /v1/completions : echo=true does NOT return prompt-
#     logprobs in this llama.cpp build (only generated-token logprobs)
#   - llama-perplexity : directly usable, produces per-chunk NLL at the
#     cost of padding bias (see below)
#
# Repeat-pad bias :
#   Padding by repeating the text means chunks 2..K benefit from KV-cache
#   memory of chunk 1. This LOWERS absolute NLL (more predictable) but
#   the effect applies identically to CSL and EN, so the m₂ RATIO is
#   approximately unbiased. Documented in DECISIONS.md.
#
# Tradeoffs vs RealBackend (llama-cpp-python) :
#   + no pip install ; binaries ship with llama.cpp releases
#   + works with Python 3.14 (no native build)
#   + reproducible via pinned binary + GGUF SHA
#   - chunk-level NLL (not per-token) ; bootstrap resamples over chunks
#   - repeat-pad bias (same for CSL+EN → ratio unbiased)

class CliBackend:
    PPL_CTX = 64              # chunk size ; keeps fixtures > 2*ctx after padding
    MIN_TOKENS = 2 * PPL_CTX  # minimum token count llama-perplexity accepts
    MAX_PAD_REPEATS = 32      # safety cap ; fixtures are small so repeats few

    def __init__(self, spec: m2_models.ModelSpec):
        import shutil
        self.spec = spec
        path = spec.cached_path
        if not path.exists():
            raise FileNotFoundError(
                f"{spec.name} GGUF not at {path}. Run scripts/m2_install_models.sh."
            )
        cands = [
            "D:/llama.cpp/llama-perplexity.exe",
            "D:/llama.cpp/llama-perplexity",
            shutil.which("llama-perplexity") or "",
        ]
        self.ppl_bin = next((c for c in cands if c and Path(c).exists()), "")
        if not self.ppl_bin:
            raise FileNotFoundError(
                "llama-perplexity.exe not found ; install D:/llama.cpp/ bundle"
            )
        self.sha = m2_models.sha256_of_file(path) if path.exists() else "UNSET"
        print(f"[cli] using {self.ppl_bin} + {path.name} (ctx={self.PPL_CTX})",
              file=sys.stderr)

    @staticmethod
    def _approx_tokens(text: str) -> int:
        # Crude estimate : ~3.5 utf-8 bytes per token (over English) ; CSL
        # glyphs inflate byte count but also inflate token count similarly.
        return max(1, int(len(text.encode("utf-8")) / 3.5))

    def _pad_repeat(self, text: str) -> tuple[str, int]:
        """Return (padded_text, n_repeats) s.t. approx-tokens >= MIN_TOKENS."""
        approx = self._approx_tokens(text)
        if approx >= self.MIN_TOKENS:
            return text, 1
        repeats = min(
            self.MAX_PAD_REPEATS,
            max(2, (self.MIN_TOKENS // max(1, approx)) + 1),
        )
        # newline separator prevents token-merge across repeat-boundaries
        padded = ("\n".join([text] * repeats)).rstrip() + "\n"
        return padded, repeats

    def token_nll(self, text: str) -> list[TokenNLL]:
        """Run llama-perplexity on padded text ; return per-chunk NLL."""
        import subprocess, tempfile, re as _re
        padded, repeats = self._pad_repeat(text)
        with tempfile.NamedTemporaryFile(
            "w", suffix=".txt", delete=False, encoding="utf-8"
        ) as f:
            f.write(padded)
            tmp = f.name
        try:
            cmd = [
                self.ppl_bin,
                "--model", str(self.spec.cached_path),
                "-f", tmp,
                "--ctx-size", str(self.PPL_CTX),
                "--ppl-output-type", "0",
                "--seed", str(SEED_DEFAULT),
                "--n-gpu-layers", "999",    # Vulkan Arc A770
                "--no-mmap",
            ]
            rc = subprocess.run(
                cmd, capture_output=True, text=True, timeout=600,
                encoding="utf-8", errors="replace",
            )
            out = (rc.stdout or "") + (rc.stderr or "")
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass

        # Per-chunk PPLs : "[1]5.64,[2]5.09,[3]4.87,..."
        chunk_vals = _re.findall(r"\[\d+\]\s*([0-9]+\.?[0-9]*)", out)
        if not chunk_vals:
            print(f"[cli] WARN : no chunk PPLs found (text={text[:60]!r})\n"
                  f"  tail: {out[-300:]}", file=sys.stderr)
            return []
        out_toks: list[TokenNLL] = []
        for i, v in enumerate(chunk_vals):
            ppl = float(v)
            nll = math.log(ppl) if ppl > 0 else 0.0
            out_toks.append(TokenNLL(
                token_id=i,
                token_str=f"[chunk{i+1}/n={len(chunk_vals)}]",
                nll=nll,
            ))
        return out_toks


def load_csl_file(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def load_paraphrase(stem: str) -> str | None:
    """Load eval/paraphrases/<base>.en preferring `.en` over `.md`.

    Naming : `<base>.en` in eval/paraphrases/.
    Fallback : existing eval/<base>_EN.md (strip Markdown headers)."""
    base = CSL_TO_PARAPHRASE.get(stem)
    if base:
        p = PARA_DIR / f"{base}.en"
        if p.exists():
            return p.read_text(encoding="utf-8")
    legacy = EVAL_DIR / f"{stem}_EN.md"
    if legacy.exists():
        text = legacy.read_text(encoding="utf-8")
        return strip_md_headers(text)
    return None


HDR_RE = re.compile(r"^#+ .*$", re.MULTILINE)

def strip_md_headers(md: str) -> str:
    # Keep paragraph content ; drop heading syntax + blank-line padding.
    out = HDR_RE.sub("", md)
    out = re.sub(r"\n{3,}", "\n\n", out)
    return out.strip() + "\n"


# ---------- Bootstrap CI ----------

def bootstrap_m2(
    csl_nlls: list[float],
    en_nlls:  list[float],
    n_resamples: int = BOOTSTRAP_DEFAULT,
    seed: int = SEED_DEFAULT,
) -> tuple[float, float, float]:
    """Returns (m2, ci_low, ci_high) at 95% via percentile method."""
    if not csl_nlls or not en_nlls:
        return math.nan, math.nan, math.nan

    rng = random.Random(seed)
    base_m2 = (sum(csl_nlls) / len(csl_nlls)) / (sum(en_nlls) / len(en_nlls))
    resampled: list[float] = []
    n_csl = len(csl_nlls)
    n_en  = len(en_nlls)
    for _ in range(n_resamples):
        rs_csl = [csl_nlls[rng.randrange(n_csl)] for _ in range(n_csl)]
        rs_en  = [en_nlls[rng.randrange(n_en)]   for _ in range(n_en)]
        m  = (sum(rs_csl) / n_csl) / (sum(rs_en) / n_en)
        resampled.append(m)
    resampled.sort()
    lo = resampled[int(0.025 * n_resamples)]
    hi = resampled[int(0.975 * n_resamples) - 1]
    return base_m2, lo, hi


# ---------- Measurement ----------

def measure_one(
    backend: Any,
    csl_path: Path,
    en_text:  str,
    spec:     m2_models.ModelSpec,
    bootstrap_n: int,
    keep_token_nll: bool,
    seed: int,
) -> Measurement:
    t0 = time.time()

    csl_text = load_csl_file(csl_path)
    csl_nll = backend.token_nll(csl_text)
    en_nll  = backend.token_nll(en_text)

    csl_means = [t.nll for t in csl_nll]
    en_means  = [t.nll for t in en_nll]

    m2, lo, hi = bootstrap_m2(
        csl_means, en_means,
        n_resamples=bootstrap_n,
        seed=seed,
    )

    csl_mean_total = sum(csl_means) / max(1, len(csl_means))
    en_mean_total  = sum(en_means)  / max(1, len(en_means))

    meas = Measurement(
        file=csl_path.name,
        paraphrase=CSL_TO_PARAPHRASE.get(csl_path.stem.replace("_CSL", ""), csl_path.stem),
        model_key=spec.key,
        model_name=spec.name,
        model_sha=getattr(backend, "sha", "unknown"),
        csl_n_tokens=len(csl_nll),
        en_n_tokens=len(en_nll),
        csl_mean_nll=csl_mean_total,
        en_mean_nll=en_mean_total,
        m2=m2,
        m2_ci_low=lo,
        m2_ci_high=hi,
        bootstrap_n=bootstrap_n,
        seed=seed,
        elapsed_sec=round(time.time() - t0, 3),
        backend=("mock" if isinstance(backend, MockBackend)
                 else "cli" if isinstance(backend, CliBackend)
                 else "real"),
        csl_token_nll=csl_nll if keep_token_nll else [],
        en_token_nll=en_nll   if keep_token_nll else [],
    )
    return meas


# ---------- Cache ----------

def cache_key(csl_text: str, en_text: str, model_sha: str, algo_version: str) -> str:
    h = hashlib.blake2b(digest_size=32)
    h.update(csl_text.encode())
    h.update(b"|")
    h.update(en_text.encode())
    h.update(b"|")
    h.update(model_sha.encode())
    h.update(b"|")
    h.update(algo_version.encode())
    return h.hexdigest()


def cache_load(key: str) -> dict | None:
    p = CACHE_DIR / f"{key}.json"
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:
        return None


def cache_store(key: str, data: dict) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    p = CACHE_DIR / f"{key}.json"
    p.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")


# ---------- CLI ----------

def cmd_self_test() -> int:
    """Smoke: run mock backend on 2 fixtures ; assert m₂ finite + deterministic."""
    print("§ m₂ self-test (mock backend)")
    sample_csl = "§ T\n  hp : i32\n  cmp't : a → b → bool\n"
    sample_en  = "Section T defines a 32-bit integer hit-point variable and a " \
                 "comparator that takes two inputs and returns a boolean.\n"

    spec = m2_models.MODELS[0]
    be = MockBackend(spec)
    csl_nll = [t.nll for t in be.token_nll(sample_csl)]
    en_nll  = [t.nll for t in be.token_nll(sample_en)]
    m2, lo, hi = bootstrap_m2(csl_nll, en_nll, n_resamples=200, seed=42)

    print(f"  sample csl nll mean: {sum(csl_nll)/len(csl_nll):.3f} ({len(csl_nll)} toks)")
    print(f"  sample en  nll mean: {sum(en_nll)/len(en_nll):.3f} ({len(en_nll)} toks)")
    print(f"  m₂                : {m2:.4f}  [CI 95% : {lo:.4f} .. {hi:.4f}]")

    # Determinism : re-run + expect same values
    m2b, _, _ = bootstrap_m2(csl_nll, en_nll, n_resamples=200, seed=42)
    if abs(m2 - m2b) > 1e-9:
        print(f"  DET-FAIL : re-run produced {m2b:.6f} != {m2:.6f}")
        return 1
    print(f"  deterministic : yes")
    print("§ self-test PASS")
    return 0


def cmd_all_eval(args) -> int:
    csl_files = sorted(EVAL_DIR.glob("C*_CSL.csl"))
    if not csl_files:
        print("no eval/C*_CSL.csl files found", file=sys.stderr)
        return 2

    models = [m2_models.MODEL_BY_KEY[k] for k in (args.model or ["small","medium","large"])
              if k in m2_models.MODEL_BY_KEY]
    if not models:
        print(f"no matching models: {args.model}", file=sys.stderr)
        return 2

    backend_kind = args.backend
    all_measurements: list[Measurement] = []

    for spec in models:
        try:
            be = load_backend(spec, backend_kind)
        except Exception as e:
            print(f"[skip] {spec.key}: {e}", file=sys.stderr)
            continue
        for csl_path in csl_files:
            stem = csl_path.stem.replace("_CSL", "")
            en = load_paraphrase(stem)
            if en is None:
                print(f"[skip] {stem}: no paraphrase", file=sys.stderr)
                continue
            meas = measure_one(
                be, csl_path, en, spec,
                args.bootstrap, args.token_nll, args.seed,
            )
            all_measurements.append(meas)
            print(f"{spec.key:6s}  {csl_path.name:30s}  "
                  f"m2={meas.m2:.4f}  CI=[{meas.m2_ci_low:.4f},{meas.m2_ci_high:.4f}]  "
                  f"{meas.elapsed_sec:.1f}s")

    # Write baseline table
    baseline = {
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "backend": backend_kind,
        "seed": args.seed,
        "bootstrap_n": args.bootstrap,
        "measurements": [m.compact() for m in all_measurements],
    }
    if args.json:
        print(json.dumps(baseline, indent=2, ensure_ascii=False))
    else:
        EVAL_DIR.mkdir(parents=True, exist_ok=True)
        BASELINE.write_text(
            json.dumps(baseline, indent=2, ensure_ascii=False), encoding="utf-8"
        )
        print(f"\n§ baseline written → {BASELINE}")

    # stratified-target check (informational)
    return 0


def cmd_single(args) -> int:
    csl_path = Path(args.file)
    if not csl_path.exists():
        print(f"file not found: {csl_path}", file=sys.stderr)
        return 2
    stem = csl_path.stem.replace("_CSL", "")
    en = load_paraphrase(stem)
    if en is None and args.paraphrase:
        en = Path(args.paraphrase).read_text(encoding="utf-8")
    if en is None:
        print(f"no paraphrase for {stem} — "
              f"expected eval/paraphrases/{CSL_TO_PARAPHRASE.get(stem, stem)}.en", file=sys.stderr)
        return 2

    keys = args.model or ["small","medium","large"]
    results: list[Measurement] = []
    for key in keys:
        spec = m2_models.MODEL_BY_KEY.get(key)
        if spec is None:
            print(f"[skip] unknown model key: {key}", file=sys.stderr)
            continue
        try:
            be = load_backend(spec, args.backend)
        except Exception as e:
            print(f"[skip] {spec.key}: {e}", file=sys.stderr)
            continue
        meas = measure_one(be, csl_path, en, spec, args.bootstrap, args.token_nll, args.seed)
        results.append(meas)

    if args.json:
        out = [asdict(m) for m in results]
        # slim per-token fields for stdout
        for d in out:
            d["csl_token_nll"] = f"[{len(d['csl_token_nll'])} tokens]"
            d["en_token_nll"]  = f"[{len(d['en_token_nll'])} tokens]"
        print(json.dumps(out, indent=2, ensure_ascii=False))
    else:
        for m in results:
            print(f"{m.model_key:6s}  m2={m.m2:.4f}  "
                  f"CI=[{m.m2_ci_low:.4f},{m.m2_ci_high:.4f}]  "
                  f"tokens csl={m.csl_n_tokens} en={m.en_n_tokens}  "
                  f"{m.elapsed_sec:.1f}s")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="m₂ perplexity metric (T25)")
    ap.add_argument("file", nargs="?", help="CSL file (or use --all-eval)")
    ap.add_argument("--paraphrase", help="override paraphrase path")
    ap.add_argument("--model", action="append",
                    help="model key(s) : small | medium | large (repeatable)")
    ap.add_argument("--all-eval", action="store_true", help="run across eval/C*_CSL.csl")
    ap.add_argument("--bootstrap", type=int, default=BOOTSTRAP_DEFAULT,
                    help="bootstrap CI resample count")
    ap.add_argument("--seed", type=int, default=SEED_DEFAULT)
    ap.add_argument("--json", action="store_true", help="machine-readable")
    ap.add_argument("--token-nll", action="store_true",
                    help="include per-token NLL in output")
    ap.add_argument("--backend", choices=["real", "mock", "cli"], default="mock",
                    help="'real' llama-cpp-python (token-NLL, needs pybind) | "
                         "'cli' llama-perplexity.exe subprocess (aggregate-NLL, "
                         "Py3.14-compatible) | 'mock' (deterministic, fast)")
    ap.add_argument("--self-test", action="store_true", help="smoke self-test")
    args = ap.parse_args()

    if args.self_test:
        return cmd_self_test()
    if args.all_eval:
        return cmd_all_eval(args)
    if args.file:
        return cmd_single(args)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
