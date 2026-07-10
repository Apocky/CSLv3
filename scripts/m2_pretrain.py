#!/usr/bin/env python3
"""§ Session-18 D-scaffold : from-scratch CSLv3-native transformer pretrain.

This is the first step on the long D-track : rather than fine-tune an
off-the-shelf LLM (Sessions 14-17), pretrain a small transformer from
scratch on CSLv3 + CSLv3-paraphrase content. The multi-month research
question is whether a model whose INITIAL parameters were only ever
exposed to CSLv3-shaped data develops a token-distribution internal
to the notation rather than the partially-relearned CSL-bias of a
fine-tuned adapter.

Session-18 goal is the SCAFFOLD : minimal byte-pair-encoding tokenizer
+ nanoGPT-style transformer + 1-epoch smoke-test on the ~18-pair
corpus. This is NOT a useful model — the corpus is laughably small
for from-scratch pretraining — but it demonstrates the pipeline
works end-to-end, which is the prerequisite for a proper Session-19+
pretraining run at 100M-1B-token scale.

Architecture (conservative nanoGPT recipe) :
  n_layer = 4 , n_head = 4 , n_embd = 128
  block_size = 256 , vocab = byte-level (256 tokens + specials)
  ≈ 1 M params at this config ; scales up trivially by bumping n_*

Usage :
  python scripts/m2_pretrain.py --smoke          # 1-epoch smoke test
  python scripts/m2_pretrain.py --train --steps=5000
  python scripts/m2_pretrain.py --sample --model=artifacts/pretrain/smoke

Deterministic under seed=20260417.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
import time
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVAL = ROOT / "eval"
PARA = EVAL / "paraphrases"
CORPUS_V2 = ROOT / "training_data" / "corpus_v2"
OUT_DIR = ROOT / "artifacts" / "pretrain"


# ---------- corpus assembly ----------

def gather_corpus_bytes() -> bytes:
    """Concatenate every CSL fixture + every EN paraphrase into one byte-
    stream. Session-18 uses byte-level tokenization for speed of
    scaffolding ; Session-19+ can swap in a proper BPE."""
    parts: list[bytes] = []
    csl_files = sorted(EVAL.glob("C*_CSL.csl"))
    if CORPUS_V2.exists():
        csl_files += sorted(CORPUS_V2.glob("C*_CSL.csl"))
    en_files = sorted(PARA.glob("*.en"))
    if CORPUS_V2.exists():
        en_files += sorted(CORPUS_V2.glob("*.en"))
    for f in csl_files + en_files:
        parts.append(f.read_bytes())
        parts.append(b"\n\n\0")   # record-separator
    return b"".join(parts)


# ---------- tokenizer (byte-level + 3 specials) ----------

PAD, BOS, EOS = 256, 257, 258
VOCAB = 259

def encode(data: bytes) -> list[int]:
    return list(data)  # each byte is its own token 0..255

def decode(ids) -> bytes:
    return bytes(i for i in ids if 0 <= i < 256)


# ---------- model ----------

@dataclass
class Config:
    n_layer: int = 4
    n_head: int = 4
    n_embd: int = 128
    block_size: int = 256
    vocab: int = VOCAB
    dropout: float = 0.1
    bias: bool = False


def build_model(cfg: Config):
    import torch, torch.nn as nn

    class CausalSelfAttention(nn.Module):
        def __init__(self, cfg: Config):
            super().__init__()
            assert cfg.n_embd % cfg.n_head == 0
            self.n_head = cfg.n_head
            self.n_embd = cfg.n_embd
            self.c_attn = nn.Linear(cfg.n_embd, 3 * cfg.n_embd, bias=cfg.bias)
            self.c_proj = nn.Linear(cfg.n_embd, cfg.n_embd, bias=cfg.bias)
            self.dropout = nn.Dropout(cfg.dropout)
            mask = torch.tril(torch.ones(cfg.block_size, cfg.block_size))
            self.register_buffer("mask", mask.view(1, 1, cfg.block_size, cfg.block_size))

        def forward(self, x):
            import torch.nn.functional as F
            B, T, C = x.size()
            q, k, v = self.c_attn(x).split(self.n_embd, dim=2)
            q = q.view(B, T, self.n_head, C // self.n_head).transpose(1, 2)
            k = k.view(B, T, self.n_head, C // self.n_head).transpose(1, 2)
            v = v.view(B, T, self.n_head, C // self.n_head).transpose(1, 2)
            att = (q @ k.transpose(-2, -1)) * (1.0 / math.sqrt(k.size(-1)))
            att = att.masked_fill(self.mask[:, :, :T, :T] == 0, float("-inf"))
            att = F.softmax(att, dim=-1)
            att = self.dropout(att)
            y = (att @ v).transpose(1, 2).contiguous().view(B, T, C)
            return self.c_proj(y)

    class MLP(nn.Module):
        def __init__(self, cfg: Config):
            super().__init__()
            self.c_fc = nn.Linear(cfg.n_embd, 4 * cfg.n_embd, bias=cfg.bias)
            self.c_proj = nn.Linear(4 * cfg.n_embd, cfg.n_embd, bias=cfg.bias)
            self.dropout = nn.Dropout(cfg.dropout)
            self.gelu = nn.GELU()

        def forward(self, x):
            return self.dropout(self.c_proj(self.gelu(self.c_fc(x))))

    class Block(nn.Module):
        def __init__(self, cfg: Config):
            super().__init__()
            self.ln1 = nn.LayerNorm(cfg.n_embd, bias=cfg.bias)
            self.ln2 = nn.LayerNorm(cfg.n_embd, bias=cfg.bias)
            self.attn = CausalSelfAttention(cfg)
            self.mlp = MLP(cfg)

        def forward(self, x):
            x = x + self.attn(self.ln1(x))
            x = x + self.mlp(self.ln2(x))
            return x

    class CSLGPT(nn.Module):
        def __init__(self, cfg: Config):
            super().__init__()
            self.cfg = cfg
            self.tok_emb = nn.Embedding(cfg.vocab, cfg.n_embd)
            self.pos_emb = nn.Embedding(cfg.block_size, cfg.n_embd)
            self.drop = nn.Dropout(cfg.dropout)
            self.blocks = nn.ModuleList([Block(cfg) for _ in range(cfg.n_layer)])
            self.ln_f = nn.LayerNorm(cfg.n_embd, bias=cfg.bias)
            self.head = nn.Linear(cfg.n_embd, cfg.vocab, bias=False)
            # weight tying
            self.head.weight = self.tok_emb.weight

        def forward(self, idx, targets=None):
            import torch.nn.functional as F
            B, T = idx.size()
            pos = torch.arange(0, T, dtype=torch.long, device=idx.device)
            x = self.drop(self.tok_emb(idx) + self.pos_emb(pos))
            for blk in self.blocks:
                x = blk(x)
            x = self.ln_f(x)
            logits = self.head(x)
            loss = None
            if targets is not None:
                loss = F.cross_entropy(
                    logits.view(-1, logits.size(-1)),
                    targets.view(-1),
                    ignore_index=-100,
                )
            return logits, loss

    import torch
    return CSLGPT(cfg)


# ---------- training loop ----------

def train(args) -> int:
    import torch

    torch.manual_seed(args.seed)
    random.seed(args.seed)

    cfg = Config()
    model = build_model(cfg)
    n_params = sum(p.numel() for p in model.parameters())
    print(f"[model] layers={cfg.n_layer} heads={cfg.n_head} embd={cfg.n_embd} "
          f"block={cfg.block_size} params={n_params/1e6:.2f}M")

    data = gather_corpus_bytes()
    token_ids = encode(data)
    tokens = torch.tensor(token_ids, dtype=torch.long)
    print(f"[corpus] {len(data):,} bytes, {len(token_ids):,} tokens")

    if len(tokens) < cfg.block_size + 1:
        print(f"[fatal] corpus too small for block_size={cfg.block_size}",
              file=sys.stderr)
        return 1

    opt = torch.optim.AdamW(model.parameters(), lr=args.lr, betas=(0.9, 0.95))

    def sample_batch(batch_size: int):
        idxs = torch.randint(0, len(tokens) - cfg.block_size - 1, (batch_size,))
        xb = torch.stack([tokens[i:i + cfg.block_size] for i in idxs])
        yb = torch.stack([tokens[i + 1:i + 1 + cfg.block_size] for i in idxs])
        return xb, yb

    total_steps = args.steps if not args.smoke else 50
    t0 = time.time()
    for step in range(total_steps):
        x, y = sample_batch(args.batch_size)
        logits, loss = model(x, y)
        opt.zero_grad(set_to_none=True)
        loss.backward()
        opt.step()
        if step % max(1, total_steps // 20) == 0 or step == total_steps - 1:
            dt = time.time() - t0
            print(f"[train] step {step:5d}/{total_steps}  loss={loss.item():.4f}  "
                  f"{dt:.1f}s")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tag = "smoke" if args.smoke else f"{args.steps}"
    save_path = OUT_DIR / tag
    save_path.mkdir(exist_ok=True)
    torch.save({"model": model.state_dict(), "config": cfg.__dict__},
               save_path / "ckpt.pt")
    (save_path / "config.json").write_text(json.dumps(cfg.__dict__, indent=2))
    print(f"[save] {save_path / 'ckpt.pt'}")
    return 0


def sample(args) -> int:
    import torch, torch.nn.functional as F
    mdir = Path(args.model)
    if not (mdir / "ckpt.pt").exists():
        print(f"[fatal] {mdir / 'ckpt.pt'} missing", file=sys.stderr)
        return 2
    ck = torch.load(mdir / "ckpt.pt", map_location="cpu", weights_only=False)
    cfg = Config(**ck["config"])
    model = build_model(cfg)
    model.load_state_dict(ck["model"])
    model.eval()

    prompt = args.prompt.encode("utf-8") if args.prompt else b"\xc2\xa7 "
    idx = torch.tensor([list(prompt)], dtype=torch.long)
    with torch.no_grad():
        for _ in range(args.n):
            ctx = idx[:, -cfg.block_size:]
            logits, _ = model(ctx)
            logits = logits[:, -1, :] / max(0.01, args.temperature)
            probs = F.softmax(logits, dim=-1)
            nxt = torch.multinomial(probs, num_samples=1)
            idx = torch.cat([idx, nxt], dim=1)
    out = decode(idx[0].tolist())
    print(out.decode("utf-8", errors="replace"))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--smoke", action="store_true",
                    help="1-epoch-ish smoke test (50 steps)")
    ap.add_argument("--train", action="store_true", help="run training")
    ap.add_argument("--steps", type=int, default=2000)
    ap.add_argument("--batch-size", type=int, default=8)
    ap.add_argument("--lr", type=float, default=3e-4)
    ap.add_argument("--seed", type=int, default=20260417)
    ap.add_argument("--sample", action="store_true", help="generate from a ckpt")
    ap.add_argument("--model", default=str(OUT_DIR / "smoke"))
    ap.add_argument("--prompt", default="")
    ap.add_argument("--n", type=int, default=200, help="sample tokens to emit")
    ap.add_argument("--temperature", type=float, default=0.8)
    args = ap.parse_args()

    if args.sample:
        return sample(args)
    if args.smoke or args.train:
        return train(args)
    ap.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
