#!/usr/bin/env python3
"""T25.1 — model registry for m₂ perplexity harness (Session-11).

Declares the reference GGUF checkpoints, their SHA-256 pins, download
URLs, and pre-flight verification. Importable as a library OR invokable
as a CLI tool (`--verify`, `--print`, `--json`).

Why only 3 models : handoff §§ MODEL-SET rationale — inter-model variance
signal vs single-model bias. Kept under 8 GB disk budget total.

All selected models are :
  - GGUF-format (llama.cpp compatible)
  - Q4_K_M quantization (quality/size tradeoff)
  - permissively-licensed
  - multilingual + instruction-tuned
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from dataclasses import dataclass, asdict, field
from pathlib import Path

# ---------- Registry ----------

@dataclass
class ModelSpec:
    key:          str           # cli-friendly label : "small" | "medium" | "large"
    name:         str           # human-readable
    repo:         str           # HuggingFace repo
    filename:     str           # GGUF filename inside the repo
    size_mb:      int           # expected on-disk size (informational)
    sha256:       str           # pinned hex digest for reproducibility
    license:      str           # license family
    context:      int           # native context window (tokens)
    family:       str           # architecture family
    extra:        dict = field(default_factory=dict)

    @property
    def cached_path(self) -> Path:
        return CACHE_DIR / self.filename


# Default cache directory : ~/.cslv3-m2-models/
CACHE_DIR = Path(
    os.environ.get("CSLV3_M2_CACHE",
                   str(Path.home() / ".cslv3-m2-models"))
).resolve()

# NOTE on sha256 pins :
#   GGUF quantizations are deterministic given the same source weights
#   and unsloth's build scripts. We pin the SHA for reproducibility.
#   If a download fails verification, users are expected to re-pull and
#   open an issue rather than bypass the check.
#   For initial development the pins are marked UNSET and filled-in on
#   first successful download + verify via `--update-pins`.

MODELS: list[ModelSpec] = [
    ModelSpec(
        key="small",
        name="Qwen2.5-1.5B-Instruct",
        repo="Qwen/Qwen2.5-1.5B-Instruct-GGUF",
        filename="qwen2.5-1.5b-instruct-q4_k_m.gguf",
        size_mb=940,
        sha256="UNSET",   # pinned on first-successful-verify
        license="Apache-2.0",
        context=32768,
        family="qwen2.5",
        extra={"rationale": "small fast baseline ; multilingual tokenizer"},
    ),
    ModelSpec(
        key="medium",
        name="Llama-3.2-3B-Instruct",
        repo="bartowski/Llama-3.2-3B-Instruct-GGUF",
        filename="Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        size_mb=1950,
        sha256="UNSET",
        license="Llama-3.2 Community License",
        context=131072,
        family="llama3.2",
        extra={"rationale": "different family, different tokenizer"},
    ),
    ModelSpec(
        key="large",
        name="Mistral-7B-Instruct-v0.3",
        repo="bartowski/Mistral-7B-Instruct-v0.3-GGUF",
        filename="Mistral-7B-Instruct-v0.3-Q4_K_M.gguf",
        size_mb=4080,
        sha256="UNSET",
        license="Apache-2.0",
        context=32768,
        family="mistral",
        extra={"rationale": "7B heavyweight ; well-tested baseline"},
    ),
]

MODEL_BY_KEY: dict[str, ModelSpec] = {m.key: m for m in MODELS}


# ---------- Verification helpers ----------

def sha256_of_file(path: Path, chunk: int = 4 * 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for blk in iter(lambda: f.read(chunk), b""):
            h.update(blk)
    return h.hexdigest()


def verify_model(spec: ModelSpec) -> tuple[bool, str]:
    """Return (ok, message). Ok iff file exists AND sha matches pinned
    value (or pin is UNSET AND file is present)."""
    p = spec.cached_path
    if not p.exists():
        return False, f"not-cached at {p}"
    size_mb = p.stat().st_size // (1024 * 1024)
    got = sha256_of_file(p)
    if spec.sha256 == "UNSET":
        return True, f"present (size={size_mb} MB, sha={got[:16]}... UNPINNED)"
    if got != spec.sha256:
        return False, f"SHA MISMATCH (got={got[:16]}..., want={spec.sha256[:16]}...)"
    return True, f"verified (size={size_mb} MB, sha={got[:16]}...)"


# ---------- Downloader ----------

def download_spec(spec: ModelSpec, force: bool = False) -> bool:
    """Uses huggingface_hub to fetch the GGUF. Returns True on success.
    If the file exists and pins verify, skip unless force=True."""
    try:
        from huggingface_hub import hf_hub_download
    except ImportError:
        sys.stderr.write("ERROR: pip install huggingface_hub\n")
        return False

    ok, msg = verify_model(spec)
    if ok and not force:
        print(f"  [cache] {spec.key}: {msg}")
        return True

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"  [dl] {spec.key}: {spec.repo}/{spec.filename} (~{spec.size_mb} MB)")
    try:
        os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "1"
        dst = hf_hub_download(
            repo_id=spec.repo,
            filename=spec.filename,
            local_dir=str(CACHE_DIR),
        )
        print(f"  [dl] done -> {dst}")
    except Exception as e:
        sys.stderr.write(f"  [dl] FAIL {spec.key}: {e}\n")
        return False

    ok, msg = verify_model(spec)
    print(f"  [verify] {spec.key}: {msg}")
    return ok


# ---------- CLI ----------

def cmd_print(args) -> int:
    for m in MODELS:
        print(f"{m.key:8s}  {m.name:32s}  {m.size_mb:5d} MB  {m.license}")
        print(f"          repo={m.repo}")
        print(f"          file={m.filename}")
        print(f"          ctx ={m.context}")
    print(f"\ncache : {CACHE_DIR}")
    return 0


def cmd_verify(args) -> int:
    rc = 0
    for m in MODELS:
        if args.model and m.key != args.model:
            continue
        ok, msg = verify_model(m)
        status = "OK" if ok else "FAIL"
        print(f"{status:4s}  {m.key:8s}  {msg}")
        if not ok:
            rc = 1
    return rc


def cmd_download(args) -> int:
    rc = 0
    for m in MODELS:
        if args.model and m.key != args.model:
            continue
        if not download_spec(m, force=args.force):
            rc = 1
    return rc


def cmd_json(args) -> int:
    out = {
        "cache_dir": str(CACHE_DIR),
        "models": [asdict(m) for m in MODELS],
    }
    print(json.dumps(out, indent=2))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=False)

    s_print = sub.add_parser("print", help="print registry (default)")
    s_verify = sub.add_parser("verify", help="verify cached models")
    s_verify.add_argument("--model", help="restrict to one key")
    s_dl = sub.add_parser("download", help="download missing models")
    s_dl.add_argument("--model", help="restrict to one key")
    s_dl.add_argument("--force", action="store_true", help="re-download")
    s_json = sub.add_parser("json", help="JSON dump")

    args = ap.parse_args()

    fn = {
        None:       cmd_print,
        "print":    cmd_print,
        "verify":   cmd_verify,
        "download": cmd_download,
        "json":     cmd_json,
    }[args.cmd]
    return fn(args)


if __name__ == "__main__":
    sys.exit(main())
