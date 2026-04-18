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


def build_training_corpus(mode: str = "joint") -> list[dict]:
    """Assemble training examples from the corpus.

    `mode` (Session-16 isolation experiment) :

      "joint"    : each example is (EN-paraphrase prompt, CSL completion).
                   Training loss covers ONLY the CSL-completion portion
                   (prompt is masked with -100). This is the Session-14
                   baseline recipe. Teaches "given EN intent, produce CSL".

      "csl-only" : each example is a single CSL fixture as both prompt
                   and completion. No masking ← full next-token loss on
                   CSL. Teaches "predict CSL token-stream".

      "en-only"  : each example is a single EN paraphrase. Full next-
                   token loss on EN. Teaches "predict EN token-stream".

    The CSL-only vs EN-only split isolates which side of the loss an
    adapter is learning from, per the Session-15-handoff isolation
    recommendation. Joint training confounds the two.
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
        m = discover_mode(csl)
        if mode == "joint":
            pairs.append({
                "prompt":     en.read_text(encoding="utf-8"),
                "completion": csl.read_text(encoding="utf-8"),
                "meta":       {"fixture": stem, "mode": m, "train_mode": "joint"},
            })
        elif mode == "csl-only":
            pairs.append({
                "prompt":     "",
                "completion": csl.read_text(encoding="utf-8"),
                "meta":       {"fixture": stem, "mode": m, "train_mode": "csl-only"},
            })
        elif mode == "en-only":
            pairs.append({
                "prompt":     "",
                "completion": en.read_text(encoding="utf-8"),
                "meta":       {"fixture": stem, "mode": m, "train_mode": "en-only"},
            })
        else:
            raise ValueError(f"unknown mode : {mode}")
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
    print(f"[corpus] wrote {len(pairs)} pairs -> {ds_path}")
    return ds_path


def train(args) -> int:
    ok, why = check_env()
    if not ok:
        print(f"[env] cannot train: {why}")
        print("[env] wheels for Python 3.14 pending ; run on a 3.12 env or wait")
        print("[corpus] building training set anyway (usable by any trainer)")
        pairs = build_training_corpus(mode=args.mode)
        write_training_dataset(pairs, TRAINING_DIR / args.mode)
        return 2

    # Imports are lazy so --help works even without packages.
    import torch
    from transformers import (AutoModelForCausalLM, AutoTokenizer,
                               TrainingArguments, Trainer,
                               DataCollatorForLanguageModeling)
    from peft import LoraConfig, get_peft_model, TaskType
    from datasets import Dataset

    print(f"[env] torch {torch.__version__} ; cuda={torch.cuda.is_available()}")
    print(f"[env] mode={args.mode} base={args.base} rank={args.rank}")

    pairs = build_training_corpus(mode=args.mode)
    ds_path = write_training_dataset(pairs, TRAINING_DIR / args.mode)

    # Build prompt/completion → completion-only-loss dataset.
    tokenizer = AutoTokenizer.from_pretrained(args.base, use_fast=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    def tokenize_row(ex):
        # For joint mode : prompt is non-empty (EN), completion is CSL, and
        # we mask labels up to prompt_len. For csl-only / en-only mode :
        # prompt is empty, so prompt_len = 0 and the whole completion is
        # trained against (no masking).
        if ex["prompt"]:
            full = ex["prompt"] + "\n---\n" + ex["completion"]
            prompt_only = tokenizer(ex["prompt"] + "\n---\n",
                                    truncation=True, max_length=args.max_len,
                                    padding=False, return_tensors=None)
            prompt_len = len(prompt_only["input_ids"])
        else:
            full = ex["completion"]
            prompt_len = 0
        enc = tokenizer(full, truncation=True, max_length=args.max_len,
                        padding="max_length", return_tensors=None)
        labels = [-100] * prompt_len + enc["input_ids"][prompt_len:]
        labels = labels[:len(enc["input_ids"])]
        # mask pad-tokens from loss
        labels = [-100 if tok == tokenizer.pad_token_id else lbl
                  for tok, lbl in zip(enc["input_ids"], labels)]
        enc["labels"] = labels
        return enc

    ds = Dataset.from_list(pairs).map(tokenize_row, remove_columns=["prompt", "completion", "meta"])
    # Small corpus : skip train/test split. Train on all 10 pairs.
    split = {"train": ds}

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

    # Session-16 : each run goes under ARTIFACTS/<mode>[_<rank>]/
    suffix = args.mode
    if args.rank != 16: suffix += f"_r{args.rank}"
    out_dir = ARTIFACTS / suffix
    out_dir.mkdir(parents=True, exist_ok=True)
    targs = TrainingArguments(
        output_dir=str(out_dir),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=1,
        gradient_accumulation_steps=4,
        learning_rate=args.lr,
        warmup_steps=5,      # small corpus ; tiny warmup
        lr_scheduler_type="cosine",
        logging_steps=1,
        save_strategy="no",  # save once manually at end
        eval_strategy="no",  # small corpus ; train on all 10 pairs
        bf16=torch.cuda.is_available(),
        seed=args.seed,
        report_to=[],
    )
    trainer = Trainer(
        model=model,
        args=targs,
        train_dataset=split["train"],
        data_collator=DataCollatorForLanguageModeling(tokenizer, mlm=False),
    )
    trainer.train()
    final_dir = out_dir / "final"
    trainer.save_model(str(final_dir))
    tokenizer.save_pretrained(str(final_dir))
    print(f"[train] adapter saved -> {final_dir}")
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
                    help="only emit training_data/<mode>/csl_corpus.jsonl, no training")
    ap.add_argument("--mode", choices=["joint", "csl-only", "en-only"],
                    default="joint",
                    help="isolation-experiment mode (Session-16) : joint "
                         "trains on EN->CSL prompt/completion pairs ; csl-only "
                         "and en-only train pure LM loss on respective halves")
    args = ap.parse_args()

    if args.build_corpus_only:
        pairs = build_training_corpus(mode=args.mode)
        write_training_dataset(pairs, TRAINING_DIR / args.mode)
        return 0

    if args.eval_only:
        print("[eval-only] post-tune re-run not yet wired ; skeleton only")
        return 2

    return train(args)


if __name__ == "__main__":
    sys.exit(main())
