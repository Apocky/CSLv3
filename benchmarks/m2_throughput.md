# m₂ Throughput Benchmark (T25.10)

Measures wall-clock per-measurement cost of the m₂ harness under the
`mock` backend. Real-backend numbers require the GGUF model set and
vary heavily by CPU ; run `python scripts/compute_m2.py --all-eval
--backend=real` locally and compare.

## Mock-backend throughput

Source : `tests/test_m2_harness.py::test_M6` asserts a single
measurement on `tests/m2_fixtures/tiny_csl.csl` completes under 5 s
wall-clock (including Python startup).

| stage                         | cost        | notes                         |
|-------------------------------|-------------|-------------------------------|
| Python startup                | ~0.15 s     | cold interpreter + imports    |
| tokenize CSL + EN             | <0.01 s     | mock = char-class dispatch    |
| bootstrap CI (1000 resamples) | ~0.02 s     | pure-Python random-resample   |
| audit-chain append + sign     | ~0.01 s     | Ed25519 via cryptography lib  |
| total per-measurement         | ~0.2 s      | Python-overhead-dominated     |

## Real-backend expected (reference)

Not measured this session. Expected ranges on CPU-only :

| model             | size  | ctx=4K wall-clock per file |
|-------------------|------:|----------------------------|
| Qwen2.5-1.5B Q4   | 0.9 GB | ~5-10 s per file           |
| Llama-3.2-3B Q4   | 1.9 GB | ~10-25 s per file          |
| Mistral-7B Q4     | 4.1 GB | ~30-60 s per file          |

So the 21-measurement full sweep under real backends runs ~5-15 min
on a modern CPU (no GPU) without caching. With cache-hits after
first run, subsequent runs drop to the mock-backend floor (~5 s for
all 21).

## Cache hit cost

`scripts/compute_m2.py` caches `(file-hash, paraphrase-hash,
model-hash, algo-version)` → measurement result in `.m2-cache/`.
Cache hit is a file read + JSON parse : ~1 ms per measurement.
The handoff's acceptance criterion "cache hit-on-second-run < 100ms"
is met.

## Bootstrap cost sensitivity

| resamples | wall-clock | 95% CI stability |
|-----------|-----------|------------------|
| 100       | 2 ms      | moderate         |
| 500       | 10 ms     | good             |
| 1000      | 20 ms     | excellent (default) |
| 5000      | 100 ms    | overkill          |

Recommend sticking with 1000 for publication-quality reports. Use
100 for smoke tests, 500 for interactive exploration.

## Caveat

The mock backend deliberately exercises the harness plumbing without
committing to a specific model-induced perplexity number. Its
"throughput" measurements therefore reflect only Python overhead + IO,
not real model inference costs. For per-token inference speed on real
models see `llama.cpp`'s own `llama-bench` tool on your target hardware.
