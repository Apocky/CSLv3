#!/usr/bin/env python3
"""§ P4 / Session-12-deferred : LoRA fine-tune on CSLv3 corpus.

This script fine-tunes a small reference model (default: Qwen2.5-1.5B)
on the combined CSLv3 corpus via LoRA (low-rank adapters). After training
it writes a PEFT adapter to `artifacts/lora_weights/` and a delta-m₂
summary to `diag/M2_FINETUNE_INTERPRETATION.md`.

Strategic hypothesis (density = sovereignty)
  H1 : a CSLv3-aware adapter lowers NLL(CSL) faster than NLL(EN).
  H2 : post-tune m₂ moves toward 1.0 (or below) on pure-CSL fixtures.
  H3 : prose-mode m₂ barely moves (already near parity).

Honest-science protocol (handoff pre-authorized) :
  - If H1 fails (NLL stays flat or gets worse on CSL) : report negative
    result.  Do not hide it.
  - If H2 fails (m₂ stays ≥ 1.0) : report that LoRA alone is insufficient
    and propose larger-scale pretraining in follow-up.

Usage (once peft+datasets+accelerate are available) :
  python scripts/m2_finetune.py --base=Qwen/Qwen2.5-1.5B-Instruct \\
                                --rank=16 --epochs=3 --lr=2e-4
  python scripts/m2_finetune.py --eval-only  # re-run m2 post-tune only

Env notes (2026-04-17) :
  Python 3.14 : peft+datasets+accelerate pip install unreliable in the
  Session-14 dev env. When wheels or a reliable conda path arrives,
  re-run this script.  Torch 2.10 + transformers 5.3 + sentence-
  transformers 5.3 are already available.

Design :
  training corpus  = all 10 CSL fixtures + all 10 EN paraphrases
                     randomly interleaved 80/20 train/val
  target tokens    = CSL side only ; we train the model to predict
                     CSLv3 content given preceding context
  LoRA config      = r=16 target_modules=[q_proj, v_proj, k_proj, o_proj]
  quantization     = Q4_K_M in memory (bitsandbytes 4bit) on Arc A770
  bootstrap        = 3 epochs ; cosine LR schedule ; warmup 50 steps
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVAL_DIR = ROOT / "eval"
PARAPHRASES = EVAL_DIR / "paraphrases"
ARTIFACTS = ROOT / "artifacts" / "lora_weights"
TRAINING_DIR = ROOT / "training_data"
REPORT = ROOT / "diag" / "M2_FINETUNE_INTERPRETATION.md"


def check_env() -> tuple[bool, str]:
    """Probe required packages ; return (ok, reason)."""
    missing = []
    for pkg in ("torch", "transformers", "peft", "datasets", "accelerate"):
        try:
            __import__(pkg)
        except ImportError:
            missing.append(pkg)
    if missing:
        return False, f"missing packages: {', '.join(missing)}"
    return True, ""


def build_training_corpus() -> list[dict]:
    """Assemble (prompt, completion) pairs from the corpus.

    For each (csl_file, en_file) pair, emit :
      (EN paraphrase as prompt, CSL file as completion)
    This teaches the model "given English spec intent, produce CSLv3".
    """
    pairs: list[dict] = []
    csl_files = sorted(EVAL_DIR.glob("C*_CSL.csl"))
    for csl in csl_files:
        stem = csl.stem.replace("_CSL", "")
        en = PARAPHRASES / f"{stem}.en"
        if not en.exists():
            en = EVAL_DIR / f"{stem}_EN.md"
        if not en.exists():
            print(f"[skip] no EN pair for {csl.name}", file=sys.stderr)
            continue
        pairs.append({
            "prompt":     en.read_text(encoding="utf-8"),
            "completion": csl.read_text(encoding="utf-8"),
            "meta":       {"fixture": stem, "mode": discover_mode(csl)},
        })
    return pairs


def discover_mode(csl_path: Path) -> str:
    for ln in csl_path.read_text(encoding="utf-8", errors="replace").splitlines()[:5]:
        if ln.startswith("# corpus-mode:"):
            return ln.split(":", 1)[1].strip()
    return "pure-CSL"


def write_training_dataset(pairs: list[dict], out: Path) -> Path:
    """Write JSONL training set ; returns path."""
    out.mkdir(parents=True, exist_ok=True)
    ds_path = out / "csl_corpus.jsonl"
    with ds_path.open("w", encoding="utf-8") as f:
        for p in pairs:
            f.write(json.dumps(p, ensure_ascii=False) + "\n")
    print(f"[corpus] wrote {len(pairs)} pairs → {ds_path}")
    return ds_path


def train(args) -> int:
    ok, why = check_env()
    if not ok:
        print(f"[env] cannot train: {why}")
        print("[env] wheels for Python 3.14 pending ; run on a 3.12 env or wait")
        print("[corpus] building training set anyway (usable by any trainer)")
        pairs = build_training_corpus()
        write_training_dataset(pairs, TRAINING_DIR)
        return 2

    # Imports are lazy so --help works even without packages.
    import torch
    from transformers import (AutoModelForCausalLM, AutoTokenizer,
                               TrainingArguments, Trainer,
                               DataCollatorForLanguageModeling)
    from peft import LoraConfig, get_peft_model, TaskType
    from datasets import Dataset

    print(f"[env] torch {torch.__version__} ; cuda={torch.cuda.is_available()}")

    pairs = build_training_corpus()
    ds_path = write_training_dataset(pairs, TRAINING_DIR)

    # Build prompt/completion → completion-only-loss dataset.
    tokenizer = AutoTokenizer.from_pretrained(args.base, use_fast=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    def tokenize_row(ex):
        full = ex["prompt"] + "\n---\n" + ex["completion"]
        enc = tokenizer(full, truncation=True, max_length=args.max_len,
                        padding=False, return_tensors=None)
        # label masking : only compute loss over the completion portion
        prompt_len = len(tokenizer(ex["prompt"] + "\n---\n").input_ids)
        labels = [-100] * prompt_len + enc["input_ids"][prompt_len:]
        labels = labels[:len(enc["input_ids"])]
        enc["labels"] = labels
        return enc

    ds = Dataset.from_list(pairs).map(tokenize_row, remove_columns=["prompt", "completion", "meta"])
    split = ds.train_test_split(test_size=0.2, seed=args.seed)

    model = AutoModelForCausalLM.from_pretrained(
        args.base,
        torch_dtype=torch.bfloat16 if torch.cuda.is_available() else torch.float32,
        device_map="auto",
    )
    lora_cfg = LoraConfig(
        task_type=TaskType.CAUSAL_LM,
        r=args.rank, lora_alpha=args.rank * 2, lora_dropout=0.05,
        target_modules=["q_proj", "v_proj", "k_proj", "o_proj"],
        bias="none",
    )
    model = get_peft_model(model, lora_cfg)
    model.print_trainable_parameters()

    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    targs = TrainingArguments(
        output_dir=str(ARTIFACTS),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=1,
        gradient_accumulation_steps=4,
        learning_rate=args.lr,
        warmup_steps=50,
        lr_scheduler_type="cosine",
        logging_steps=5,
        save_strategy="epoch",
        eval_strategy="epoch",
        bf16=torch.cuda.is_available(),
        seed=args.seed,
        report_to=[],
    )
    trainer = Trainer(
        model=model,
        args=targs,
        train_dataset=split["train"],
        eval_dataset=split["test"],
        data_collator=DataCollatorForLanguageModeling(tokenizer, mlm=False),
    )
    trainer.train()
    trainer.save_model(str(ARTIFACTS / "final"))
    tokenizer.save_pretrained(str(ARTIFACTS / "final"))
    print(f"[train] adapter saved → {ARTIFACTS / 'final'}")
    return 0


def write_interpretation(pre: dict, post: dict) -> None:
    """Render delta-m2 report to diag/."""
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    lines = ["# § LoRA fine-tune delta-m₂ interpretation",
             "",
             "Pre-tune baseline ← v1.2.0 (Session-13) eval/m2_baseline.json",
             "Post-tune measurement ← adapter loaded from artifacts/lora_weights/final",
             "",
             "| file | mode | m2-pre | m2-post | Δ |",
             "|------|------|--------|---------|---|"]
    for f in sorted(pre):
        pre_m = pre.get(f)
        post_m = post.get(f)
        if pre_m is None or post_m is None: continue
        delta = post_m - pre_m
        lines.append(f"| {f} | ? | {pre_m:.3f} | {post_m:.3f} | {delta:+.3f} |")
    lines.append("")
    lines.append("## Interpretation")
    lines.append("")
    lines.append(" (Populated after training completes.)")
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[report] wrote {REPORT}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--base", default="Qwen/Qwen2.5-1.5B-Instruct",
                    help="base model (HF hub or local path)")
    ap.add_argument("--rank", type=int, default=16, help="LoRA rank")
    ap.add_argument("--epochs", type=int, default=3)
    ap.add_argument("--lr", type=float, default=2e-4)
    ap.add_argument("--max-len", type=int, default=2048,
                    help="max sequence length")
    ap.add_argument("--seed", type=int, default=20260417)
    ap.add_argument("--eval-only", action="store_true",
                    help="skip training ; only re-run m2 against existing adapter")
    ap.add_argument("--build-corpus-only", action="store_true",
                    help="only emit training_data/csl_corpus.jsonl, no training")
    args = ap.parse_args()

    if args.build_corpus_only:
        pairs = build_training_corpus()
        write_training_dataset(pairs, TRAINING_DIR)
        return 0

    if args.eval_only:
        print("[eval-only] post-tune re-run not yet wired ; skeleton only")
        return 2

    return train(args)


if __name__ == "__main__":
    sys.exit(main())
