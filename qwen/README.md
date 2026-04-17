# CSLv3 × Qwen3 Local Integration

Bootstrap a local Qwen3 language model with CSLv3 literacy. Uses
`llama.cpp` Vulkan backend for Intel Arc A770 (or any Vulkan-capable GPU).

## What's here

| File                              | Purpose                                       |
|-----------------------------------|-----------------------------------------------|
| `qwen.cmd`                        | One-click menu launcher (double-click from Explorer) |
| `build_system_prompt.py`          | Concatenates PRIME + CLAUDE + specs + glyph alias table → `system_prompt.txt` |
| `system_prompt.txt`               | Generated CSL3-literacy system prompt (~23k tokens) |
| `launch_qwen3_coder_next.cmd`     | Interactive chat with 80B-A3B (64K ctx, quality) |
| `launch_qwen3_14b_yarn1m.cmd`     | Interactive chat with 14B @ YaRN 1M ctx (long-context) |
| `serve_qwen3_coder_next.cmd`      | HTTP server (OpenAI-compatible) on 127.0.0.1:8080 |
| `validate_loop.py`                | Programmatic round-trip : prompt → Qwen → parser.exe cssllint → retry-on-error |

## Hardware

- **Tested on:** Intel Arc A770 (16 GB GDDR6) + 32 GB DDR5 + Windows 11
- **Backend:** llama.cpp Vulkan (`D:\llama.cpp\llama-cli.exe`)
- **Models:** `D:\models\Qwen3-Coder-Next-UD-Q3_K_M.gguf` (35.9 GB) +
             `D:\models\Qwen3-14B-Q4_K_M.gguf` (~9 GB)

## Quick start

1. **Build the system prompt** (once):
   ```
   python qwen\build_system_prompt.py
   ```
2. **Launch:** double-click `qwen\qwen.cmd` and pick 1-5 from the menu.

## What the model knows

The generated `system_prompt.txt` contains :
- `PRIME_DIRECTIVE.md` — consent-OS ethical foundation
- `CLAUDE.md` — CSLv3 operating instructions + standing directives
- `specs/12_TOKENIZER.csl` — BPE-cost decision procedure
- `specs/01_GLYPHS.csl` — 74-glyph master
- `specs/02_GRAMMAR.csl` — LL(2) slot template
- `specs/03_MORPH.csl` — compounds + morpheme stacking
- `specs/14_CSSLv3_BRIDGE.csl` — cssllint JSON contract
- `parser/glyph_aliases.json` — Unicode ↔ ASCII alias table
- A `TASK-BRIEF` block positioning the model as a Prismatic-Hydra head

Total system prompt ≈ 23 000 tokens — fits easily in either the 80B's
64K effective context or the 14B's 1M YaRN-extended context.

## Model selection guide

| Goal                                        | Use                              |
|---------------------------------------------|----------------------------------|
| Best CSL3 reasoning quality                 | 80B-A3B at 64K ctx (option 1)    |
| Ingest all 15 specs + full session history  | 14B @ YaRN 1M (option 2)         |
| API-driven workflows (VSCode Continue, etc.)| HTTP server (option 3)           |
| Validate that model output is real CSL3     | validation loop (option 5)       |

## Memory budget (80B UD-Q3_K_M)

```
Model weights (on disk)  : 35.9 GB
Weights (mmap'd)         : ~35 GB (RAM + disk-cached)
  layers 0-19 on GPU     : ~8 GB VRAM
  layers 20-63 on CPU    : ~27 GB RAM
KV cache @ 64K ctx Q8    : ~8 GB
────────────────────────
Total memory in use      : ~43 GB (tight fit on 16+32 = 48 GB)
```

At 128K ctx the KV cache grows to 16 GB and you exceed total memory.
64K is the empirical ceiling on this hardware.

## Memory budget (14B YaRN 1M)

```
Model weights (Q4_K_M)   : 9 GB  → fully GPU-offloaded
KV cache @ 1M ctx Q4     : 16 GB → GPU VRAM (tight)
────────────────────────
Total VRAM               : ~15.5 GB  (fits A770's 16 GB)
Total RAM                : minimal (weights fully on GPU)
```

## Validation loop

`validate_loop.py` runs a `user-prompt → Qwen → parser.exe cssllint`
cycle. On CSL3 diagnostic errors, the diagnostic is fed back to Qwen
as a correction prompt. Up to 3 retries before giving up.

This is the poor-man's version of the full T25 m₂ perplexity harness.
It measures *functional* CSL3 literacy (does Qwen produce valid CSL3?)
rather than *tokenization* efficiency (how many tokens per glyph?).

## Troubleshooting

**Server won't start:**
- Check `D:\llama.cpp\llama-cli.exe --list-devices` — should show Arc A770
- If no GPU listed: Intel Arc driver may be out of date

**Out-of-memory on 80B:**
- Reduce `--n-gpu-layers` from 20 to 10 (more layers on CPU, less VRAM)
- Reduce `--ctx-size` from 65536 to 32768
- Last resort: use UD-Q2_K_XL quantization (~27 GB)

**YaRN 1M OOM on 14B:**
- Lower `--ctx-size` to 524288 (500K) or 262144 (native)
- KV cache at 1M is the bottleneck — lower `--cache-type-k/v` to `q4_0`

**Slow inference on 80B:**
- Expected : ~7-15 tok/s on this hardware. llama.cpp's MoE path for
  Qwen3-Next is currently un-optimized (see llama.cpp #17751). When the
  optimization lands expect 25-40 tok/s.
- Workaround: use [ik_llama.cpp](https://github.com/ikawrakow/ik_llama.cpp)
  fork which claims ~1.9× speedup on MoE inference.

## Files on disk

```
D:\llama.cpp\             ← llama.cpp Vulkan binaries (~130 MB)
D:\models\                ← GGUF model weights (~45 GB total)
  Qwen3-Coder-Next-UD-Q3_K_M.gguf   (35.9 GB)
  Qwen3-14B-Q4_K_M.gguf             (~9 GB)

C:\...\CSLv3\qwen\        ← this integration directory
  system_prompt.txt       ← generated CSL3-literacy prompt (~87 KB)
  *.cmd                   ← launcher scripts
  *.py                    ← Python utilities
```

## License

MIT — matches the parent CSLv3 project. Model weights are governed by
Qwen / Unsloth's Apache-2 license terms ; see the respective Hugging
Face model cards.
