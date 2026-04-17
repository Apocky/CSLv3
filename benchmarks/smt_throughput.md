# SMT-Throughput Benchmark (T26.1c)

- Fixtures: 6 smt_good/*.csl
- Generated: `python tests/perf_smt_bench.py`

| solver | uncached ops | uncached ms | uncached ops/s | cached ops | cached ms | cached ops/s |
|--------|--------------|-------------|----------------|------------|-----------|--------------|
| z3 | 7 | 124 | 56.5 | 7 | 62 | 112.9 |
| cvc5 | 7 | 112 | 62.5 | 7 | 62 | 112.9 |

## Acceptance

- cached >= 100 ops/s  : gate from handoff
- uncached >= 10 ops/s : gate from handoff
