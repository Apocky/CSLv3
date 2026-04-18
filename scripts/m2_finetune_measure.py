#!/usr/bin/env python3
"""§ LoRA post-tune m₂ measurement — Session-14 / Apocky-requested.

Loads a reference base model, then loads base + LoRA adapter, computes
token-averaged NLL on each (CSL, EN-paraphrase) pair in the eval corpus,
and emits a delta-m₂ table comparing the two.

The existing `compute_m2.py` pipe uses GGUF files via llama-perplexity
subprocess. This script works directly with PyTorch HF-format weights
because that's what `peft` emits after fine-tuning, and converting to
GGUF is an extra round-trip we can skip.

Usage :
  python scripts/m2_finetune_measure.py \\
    --base=Qwen/Qwen2.5-0.5B-Instruct \\
    --adapter=artifacts/lora_weights/final

Outputs :
  eval/m2_finetune_delta.json   machine-readable
  diag/M2_FINETUNE_INTERPRETATION.md  summary + verdict
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVAL = ROOT / "eval"
PARA = EVAL / "paraphrases"
REPORT = ROOT / "diag" / "M2_FINETUNE_INTERPRETATION.md"
DELTA_JSON = EVAL / "m2_finetune_delta.json"


def _discover_pairs() -> list[dict]:
    pairs = []
    for csl in sorted(EVAL.glob("C*_CSL.csl")):
        stem = csl.stem.replace("_CSL", "")
        en = PARA / f"{stem}.en"
        if not en.exists():
            en = EVAL / f"{stem}_EN.md"
        if not en.exists():
            continue
        mode = "pure-CSL"
        for ln in csl.read_text(encoding="utf-8", errors="replace").splitlines()[:5]:
            if ln.startswith("# corpus-mode:"):
                mode = ln.split(":", 1)[1].strip()
        pairs.append({
            "stem": stem,
            "mode": mode,
            "csl_text": csl.read_text(encoding="utf-8"),
            "en_text":  en.read_text(encoding="utf-8"),
        })
    return pairs


def _mean_nll(model, tokenizer, text: str, device: str = "cpu", max_len: int = 1024) -> float:
    """Teacher-forced token-level mean NLL under causal LM."""
    import torch
    enc = tokenizer(text, truncation=True, max_length=max_len, return_tensors="pt")
    input_ids = enc["input_ids"].to(device)
    if input_ids.shape[1] < 2:
        return 0.0
    with torch.no_grad():
        out = model(input_ids, labels=input_ids)
    # HF returns mean loss over all labels ; for mean-NLL per token that's
    # exactly what we want (label-shifts handled internally).
    return float(out.loss.item())


def measure(model, tokenizer, pairs: list[dict], label: str) -> list[dict]:
    """Return list of {stem, mode, csl_nll, en_nll, m2} per pair."""
    import torch
    rows = []
    model.eval()
    for p in pairs:
        t0 = time.time()
        csl_nll = _mean_nll(model, tokenizer, p["csl_text"])
        en_nll  = _mean_nll(model, tokenizer, p["en_text"])
        m2 = csl_nll / en_nll if en_nll > 0 else float("inf")
        dt = time.time() - t0
        print(f"  [{label}] {p['stem']:26s} csl={csl_nll:.3f} en={en_nll:.3f} "
              f"m2={m2:.3f} ({dt:.1f}s)")
        rows.append({
            "stem": p["stem"],
            "mode": p["mode"],
            "csl_nll": csl_nll,
            "en_nll":  en_nll,
            "m2":      m2,
        })
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="Qwen/Qwen2.5-1.5B-Instruct")
    ap.add_argument("--adapter", action="append", default=[],
                    help="adapter path ; repeatable for multi-adapter compare. "
                         "Format : '<label>:<path>' or just '<path>' (label=dir)")
    ap.add_argument("--max-len", type=int, default=1024)
    args = ap.parse_args()

    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from peft import PeftModel

    device = "cuda" if torch.cuda.is_available() else "cpu"
    adapters = _parse_adapter_args(args.adapter)
    print(f"[env] device={device}  base={args.base}  adapters={len(adapters)}")
    for lbl, p in adapters:
        print(f"       {lbl:12s} -> {p}")

    tokenizer = AutoTokenizer.from_pretrained(args.base, use_fast=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    print("[pre] loading base model")
    base = AutoModelForCausalLM.from_pretrained(
        args.base,
        dtype=torch.float32,
        device_map=device,
    )
    pairs = _discover_pairs()

    print(f"[pre] measuring m2 on {len(pairs)} fixtures")
    pre_rows = measure(base, tokenizer, pairs, label="pre")

    # Measure each adapter.
    adapter_results = {}    # label -> list[row]
    for lbl, path in adapters:
        print(f"[post:{lbl}] attaching LoRA adapter")
        model = PeftModel.from_pretrained(base, str(ROOT / path))
        post = measure(model, tokenizer, pairs, label=f"post:{lbl}")
        adapter_results[lbl] = post
        # Detach so the next adapter starts from clean base.
        model = model.unload()  # strips LoRA weights, returns base
        del model

    # Combine deltas per-adapter.
    all_combined: dict[str, list[dict]] = {}
    for lbl, post_rows in adapter_results.items():
        combined = []
        for pre, post in zip(pre_rows, post_rows):
            combined.append({
                "stem": pre["stem"],
                "mode": pre["mode"],
                "pre":  pre,
                "post": post,
                "delta_m2": post["m2"] - pre["m2"],
                "delta_csl_nll": post["csl_nll"] - pre["csl_nll"],
                "delta_en_nll":  post["en_nll"]  - pre["en_nll"],
            })
        all_combined[lbl] = combined

    DELTA_JSON.parent.mkdir(parents=True, exist_ok=True)
    DELTA_JSON.write_text(
        json.dumps({
            "base_model": args.base,
            "adapters": {lbl: str(p) for lbl, p in adapters},
            "pre": pre_rows,
            "results": all_combined,
        }, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"[write] {DELTA_JSON}")

    render_report_multi(args, adapters, pre_rows, all_combined)
    return 0


def _parse_adapter_args(args_list: list[str]) -> list[tuple[str, str]]:
    """Parse --adapter args : 'label:path' or just 'path' (label = basename)."""
    out: list[tuple[str, str]] = []
    for a in args_list:
        if ":" in a and not a[1:3] == ":\\":  # not a Windows drive letter
            lbl, _, path = a.partition(":")
            out.append((lbl, path))
        else:
            from pathlib import PurePath
            out.append((PurePath(a).name or a, a))
    if not out:
        out.append(("default", "artifacts/lora_weights/final"))
    return out


def render_report_multi(args, adapters, pre_rows, all_combined) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    mean = lambda xs: sum(xs) / len(xs) if xs else 0.0

    pre_mean = mean([r["m2"] for r in pre_rows])

    lines = [
        "# § M2 FINETUNE INTERPRETATION — Session-16 (LoRA-proper)",
        "",
        f"generated_at : {time.strftime('%Y-%m-%d')}",
        f"base-model   : `{args.base}`",
        f"adapters     : {len(adapters)}",
    ]
    for lbl, path in adapters:
        lines.append(f"  - **{lbl}** : `{path}`")
    lines += [
        "",
        "## Summary",
        "",
        f"- pre-tune mean m₂ (base alone) : **{pre_mean:.4f}**",
        "",
        "| adapter | post mean m₂ | Δ m₂ | CSL mean ΔNLL | EN mean ΔNLL |",
        "|---------|-------------:|-----:|--------------:|-------------:|",
    ]
    for lbl, _ in adapters:
        rows = all_combined[lbl]
        post_mean = mean([r["post"]["m2"] for r in rows])
        d_mean = mean([r["delta_m2"] for r in rows])
        csl_d = mean([r["delta_csl_nll"] for r in rows])
        en_d = mean([r["delta_en_nll"] for r in rows])
        lines.append(f"| **{lbl}** | {post_mean:.4f} | {d_mean:+.4f} | {csl_d:+.4f} | {en_d:+.4f} |")

    # Hypothesis verdicts per adapter.
    lines += ["", "## Hypothesis verdicts per adapter", ""]
    for lbl, _ in adapters:
        rows = all_combined[lbl]
        csl_drop = mean([r["delta_csl_nll"] for r in rows])
        en_drop  = mean([r["delta_en_nll"] for r in rows])
        post_mean = mean([r["post"]["m2"] for r in rows])
        h1 = "✓ CONFIRMED" if csl_drop < en_drop else "✗ NOT CONFIRMED"
        h2 = ("✓ CONFIRMED" if abs(post_mean - 1.0) < abs(pre_mean - 1.0)
              else "✗ NOT CONFIRMED")
        lines.append(f"- **{lbl}** : H1 (ΔCSL < ΔEN) = {h1} ; H2 (m₂ → 1.0) = {h2}")

    # Per-file table for each adapter.
    for lbl, _ in adapters:
        rows = all_combined[lbl]
        lines += ["", f"## Per-file delta — adapter `{lbl}`", "",
                  "| file | mode | pre m₂ | post m₂ | Δ m₂ | Δ CSL-NLL | Δ EN-NLL |",
                  "|------|------|-------:|--------:|-----:|----------:|---------:|"]
        for c in rows:
            lines.append(f"| {c['stem']} | {c['mode']} | {c['pre']['m2']:.3f} | "
                         f"{c['post']['m2']:.3f} | {c['delta_m2']:+.3f} | "
                         f"{c['delta_csl_nll']:+.3f} | {c['delta_en_nll']:+.3f} |")

    # Isolation-signature analysis (key output of the experiment).
    lines += [
        "",
        "## Isolation signature",
        "",
        "If training on **csl-only** lowers CSL-NLL more than EN-NLL, the ",
        "adapter is learning the CSL token-distribution independently. "
        "Symmetrically for **en-only**. A **joint** adapter trained on "
        "(EN-prompt, CSL-completion) pairs should show mixed behaviour.",
        "",
    ]

    lines.append("```")
    for lbl, _ in adapters:
        rows = all_combined[lbl]
        csl_d = mean([r["delta_csl_nll"] for r in rows])
        en_d = mean([r["delta_en_nll"] for r in rows])
        signature = "CSL-dominant" if csl_d < en_d - 0.02 else \
                    "EN-dominant"  if en_d < csl_d - 0.02 else \
                    "balanced"
        lines.append(f"{lbl:10s}  ΔCSL={csl_d:+.4f}  ΔEN={en_d:+.4f}  => {signature}")
    lines.append("```")

    lines += [
        "",
        "## Honest-science notes",
        "",
        ("Session-14 ran at 0.5 B-CPU with joint training and reported "
         "NOT-CONFIRMED for H1 and H2. Session-16 scales to a larger base "
         f"(`{args.base}`) and adds the isolation experiment (csl-only vs "
         "en-only). The reported deltas are **on the training corpus** — "
         "data leakage is intentional because we need the m₂ signal at "
         "measurable scale with this corpus size. A generalisation "
         "experiment with a held-out fixture set is Session-17+ work."),
        "",
        ("Key result : if csl-only shows a CSL-dominant signature and "
         "en-only shows an EN-dominant signature, this confirms that a "
         "LoRA adapter is learning the token-distribution it was trained "
         "on — which is unsurprising mechanistically but has not been "
         "empirically demonstrated on the CSLv3 corpus before this session."),
        "",
        ("If the joint adapter produces a balanced signature, it indicates "
         "the prompt-masking setup is doing its job (only CSL contributes "
         "to the loss) but the adapter still ends up influencing both "
         "NLLs — likely because the base model's representation already "
         "couples the two distributions."),
        "",
        ("Per Session-12 handoff : negative results are reportable. "
         "Whichever signature emerges, the data above is the data."),
    ]
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[write] {REPORT}")


def render_report(args, combined: list[dict]) -> None:
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    # Aggregate stats
    pre_m2 = [c["pre"]["m2"] for c in combined]
    post_m2 = [c["post"]["m2"] for c in combined]
    mean = lambda xs: sum(xs) / len(xs) if xs else 0.0
    pre_mean = mean(pre_m2)
    post_mean = mean(post_m2)
    deltas = [c["delta_m2"] for c in combined]
    delta_mean = mean(deltas)

    # By mode
    modes: dict[str, list[dict]] = {}
    for c in combined:
        modes.setdefault(c["mode"], []).append(c)

    # H1 : did CSL-NLL drop faster than EN-NLL (adapter learned the notation) ?
    csl_drops = sum(1 for c in combined if c["delta_csl_nll"] < 0)
    en_drops  = sum(1 for c in combined if c["delta_en_nll"]  < 0)
    csl_drop_mean = mean([c["delta_csl_nll"] for c in combined])
    en_drop_mean  = mean([c["delta_en_nll"]  for c in combined])

    lines = [
        "# § M2 FINETUNE INTERPRETATION — Session-14",
        "",
        f"generated_at : {time.strftime('%Y-%m-%d')}",
        f"base-model   : `{args.base}`",
        f"adapter      : `{args.adapter}`",
        f"training     : 3 epochs, rank=8, lr=2e-4, corpus=10 pairs",
        "",
        "## Summary",
        "",
        f"- pre-tune mean m₂  : **{pre_mean:.4f}**",
        f"- post-tune mean m₂ : **{post_mean:.4f}**",
        f"- mean Δm₂          : **{delta_mean:+.4f}**",
        f"- CSL mean ΔNLL     : {csl_drop_mean:+.4f}  ({csl_drops}/{len(combined)} files improved)",
        f"- EN  mean ΔNLL     : {en_drop_mean:+.4f}  ({en_drops}/{len(combined)} files improved)",
        "",
        "## Hypothesis verdicts",
        "",
        ("- H1 (CSL-NLL drops faster than EN-NLL under adapter) : "
         + ("✓ CONFIRMED" if csl_drop_mean < en_drop_mean
            else "✗ NOT CONFIRMED — adapter helped EN equal-or-more than CSL")),
        ("- H2 (post-tune m₂ moves toward 1.0) : "
         + ("✓ CONFIRMED" if abs(post_mean - 1.0) < abs(pre_mean - 1.0)
            else "✗ NOT CONFIRMED")),
        "",
        "## Per-file delta table",
        "",
        "| file | mode | pre m₂ | post m₂ | Δ m₂ | Δ CSL-NLL | Δ EN-NLL |",
        "|------|------|-------:|--------:|-----:|----------:|---------:|",
    ]
    for c in combined:
        lines.append(f"| {c['stem']} | {c['mode']} | {c['pre']['m2']:.3f} | "
                     f"{c['post']['m2']:.3f} | {c['delta_m2']:+.3f} | "
                     f"{c['delta_csl_nll']:+.3f} | {c['delta_en_nll']:+.3f} |")
    lines += [
        "",
        "## By corpus-mode",
        "",
    ]
    for mode, rows in sorted(modes.items()):
        m_pre = mean([r["pre"]["m2"]  for r in rows])
        m_post = mean([r["post"]["m2"] for r in rows])
        m_delta = mean([r["delta_m2"]  for r in rows])
        lines.append(f"- **{mode}** ({len(rows)} files) : pre {m_pre:.3f} → "
                     f"post {m_post:.3f}  Δ {m_delta:+.3f}")

    lines += [
        "",
        "## Honest-science interpretation",
        "",
        ("A LoRA adapter with rank 8, trained for 3 epochs on 10 EN→CSL "
         "pairs over a 0.5 B-parameter base model, is a very small "
         "intervention. The above deltas should be read as **smoke-test** "
         "evidence that the fine-tune pipeline works end-to-end, not as "
         "a publishable claim that fine-tuning reliably moves m₂ toward "
         "1.0 on this corpus."),
        "",
        ("Meaningful follow-up experiments (Session-15+) : "
         "(a) larger base (1.5B–7B) with CUDA training ; "
         "(b) larger corpus (expand beyond 10 pairs) ; "
         "(c) rank sweep {4, 16, 32, 64} ; "
         "(d) paired fine-tune on CSL-only vs EN-only to isolate which "
         "token-distribution the adapter is actually learning ; "
         "(e) post-tune comparison against GGUF re-quant (round-trips "
         "through the existing cli-daemon harness so numbers are "
         "directly comparable to the v1.2.0 baseline)."),
        "",
        ("Per the Session-12 handoff's pre-authorization of negative-"
         "result reporting : the numbers above are reported as-measured. "
         "If H1 or H2 did not confirm, this is a data point, not a "
         "failure of the thesis — the m₂-to-density chain has "
         "independent variables (base-model capacity, fine-tune scale, "
         "corpus size) that a small-scale experiment cannot isolate."),
    ]
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[write] {REPORT}")


if __name__ == "__main__":
    sys.exit(main())
