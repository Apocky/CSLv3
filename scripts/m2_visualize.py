#!/usr/bin/env python3
"""T25.6 — m₂ HTML visualizer (Session-11).

Generates a self-contained HTML report from an m₂ baseline JSON:
  - Summary table : m₂ per-(file, model) with 95% bootstrap CI
  - Per-mode stratified-target pass/fail banner
  - Per-token NLL heatmap (when --token-nll was captured in source)
  - Side-by-side CSL/EN comparison for each pair

Usage :
  python scripts/m2_visualize.py eval/m2_baseline.json
  python scripts/m2_visualize.py run.json --out=report.html
  python scripts/m2_visualize.py eval/m2_baseline.json --token-nll eval/C1_sort_CSL.csl
"""

from __future__ import annotations

import argparse
import html
import json
import math
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

STRATIFIED_TARGETS = {
    "pure-CSL": 1.5,
    "bridge":   1.2,
    "prose":    1.05,
}

CORPUS_MODES = {
    "C1_sort":            "pure-CSL",
    "C2_nested_scopes":   "pure-CSL",
    "C3_dependent_types": "pure-CSL",
    "C4_reason_block":    "pure-CSL",
    "C5_bridge_mode":     "bridge",
    "C6_slot_grammar":    "pure-CSL",
    "C7_morpheme_stack":  "pure-CSL",
}


def nll_color(nll: float, max_nll: float) -> str:
    """Map NLL → hex color. Low NLL = green (predictable). High = red (surprising)."""
    if max_nll <= 0:
        return "#888888"
    t = min(1.0, nll / max_nll)
    r = int(50 + 200 * t)
    g = int(200 - 150 * t)
    b = int(100 - 50 * t)
    return f"#{r:02x}{g:02x}{b:02x}"


def render_heatmap_spans(per_token: list[dict], max_nll: float) -> str:
    parts = ['<div class="heatmap">']
    for tk in per_token:
        s = tk.get("token_str", "")
        n = tk.get("nll", 0.0)
        display = s.replace("\n", "↵\n").replace(" ", "·")
        bg = nll_color(n, max_nll)
        parts.append(
            f'<span class="tok" title="NLL={n:.3f}" '
            f'style="background:{bg}">{html.escape(display)}</span>'
        )
    parts.append("</div>")
    return "".join(parts)


def compute_stats(measurements: list[dict]) -> dict:
    counts = {"pass": 0, "fail": 0, "flag": 0}
    per_mode: dict[str, list[float]] = {}
    for m in measurements:
        stem = m["file"].replace("_CSL.csl", "")
        mode = CORPUS_MODES.get(stem, "pure-CSL")
        per_mode.setdefault(mode, []).append(m["m2"])
        target = STRATIFIED_TARGETS[mode]
        if m["m2"] <= target:
            counts["pass"] += 1
        else:
            counts["fail"] += 1
        if m["m2"] > 2.0:
            counts["flag"] += 1
    per_mode_summary = {
        k: {
            "n": len(v),
            "mean": round(sum(v) / len(v), 4) if v else 0.0,
            "min":  round(min(v), 4) if v else 0.0,
            "max":  round(max(v), 4) if v else 0.0,
            "target": STRATIFIED_TARGETS[k],
        }
        for k, v in per_mode.items()
    }
    return {"counts": counts, "per_mode": per_mode_summary}


STYLE = """
body { font-family: ui-monospace, "JetBrains Mono", Menlo, monospace;
       background: #0f0f14; color: #e0e0e6; max-width: 1100px; margin: 2em auto; padding: 0 2em; }
h1, h2, h3 { color: #ff8; }
table { border-collapse: collapse; margin: 1em 0; width: 100%; }
th, td { padding: 0.4em 0.8em; border: 1px solid #333; text-align: left; font-size: 0.9em; }
th { background: rgba(255,255,0,0.08); color: #ff8; }
tr:nth-child(even) { background: rgba(255,255,255,0.02); }
.pass { color: #9c6; } .fail { color: #f88; } .flag { color: #fc6; }
.banner { padding: 1em; margin: 1em 0; border-radius: 6px; background: #1a1a24; }
.banner.ok    { border-left: 4px solid #9c6; }
.banner.warn  { border-left: 4px solid #fc6; }
.banner.error { border-left: 4px solid #f88; }
.heatmap { line-height: 1.6; padding: 0.4em; border-radius: 4px;
           background: rgba(0,0,0,0.3); font-size: 0.85em; white-space: pre-wrap;
           word-wrap: break-word; }
.tok { padding: 1px 2px; margin: 1px; border-radius: 2px; color: #111; }
.ci  { color: #888; font-size: 0.85em; }
.tag { display: inline-block; padding: 2px 8px; border-radius: 10px;
       background: #2a2a3a; font-size: 0.8em; }
footer { margin-top: 3em; color: #666; font-size: 0.8em; }
"""


def render_report(baseline: dict, token_nll_file: str | None = None) -> str:
    stats = compute_stats(baseline.get("measurements", []))
    measurements = baseline.get("measurements", [])

    banner_class = "ok"
    if stats["counts"]["fail"] > 0:
        banner_class = "warn"
    if stats["counts"]["flag"] > 0:
        banner_class = "error"

    parts: list[str] = []
    parts.append(
        f"<!DOCTYPE html><html><head><meta charset=\"utf-8\">"
        f"<title>m₂ Report</title><style>{STYLE}</style></head><body>"
    )
    parts.append("<h1>§ m₂ perplexity report</h1>")
    parts.append(f"<p>Generated: {html.escape(baseline.get('generated_at', 'unknown'))}</p>")
    parts.append(f"<p>Backend : <span class=\"tag\">{html.escape(baseline.get('backend','?'))}</span> "
                 f"Seed: <span class=\"tag\">{baseline.get('seed','?')}</span> "
                 f"Bootstrap: <span class=\"tag\">{baseline.get('bootstrap_n','?')}</span></p>")

    # Summary banner
    parts.append(f'<div class="banner {banner_class}">')
    parts.append(f"<strong>Pass:</strong> {stats['counts']['pass']} "
                 f"<strong>Fail:</strong> {stats['counts']['fail']} "
                 f"<strong>Flagged:</strong> {stats['counts']['flag']}")
    parts.append("</div>")

    # Per-mode summary
    parts.append("<h2>Per-mode summary</h2>")
    parts.append("<table><thead><tr><th>mode</th><th>n</th><th>mean m₂</th>"
                 "<th>min</th><th>max</th><th>target (≤)</th></tr></thead><tbody>")
    for mode, s in stats["per_mode"].items():
        cls = "pass" if s["max"] <= s["target"] else "fail"
        parts.append(
            f"<tr><td>{mode}</td><td>{s['n']}</td><td class=\"{cls}\">{s['mean']}</td>"
            f"<td>{s['min']}</td><td>{s['max']}</td><td>{s['target']}</td></tr>"
        )
    parts.append("</tbody></table>")

    # Per-measurement table
    parts.append("<h2>Per-measurement m₂</h2>")
    parts.append("<table><thead><tr>"
                 "<th>file</th><th>mode</th><th>model</th>"
                 "<th>m₂</th><th>95% CI</th><th>n tokens (csl/en)</th>"
                 "</tr></thead><tbody>")
    for m in measurements:
        stem = m["file"].replace("_CSL.csl", "")
        mode = CORPUS_MODES.get(stem, "pure-CSL")
        target = STRATIFIED_TARGETS[mode]
        cls = "pass" if m["m2"] <= target else "fail"
        parts.append(
            f"<tr><td>{html.escape(m['file'])}</td><td>{mode}</td>"
            f"<td>{html.escape(m['model_name'])}</td>"
            f"<td class=\"{cls}\">{m['m2']:.4f}</td>"
            f"<td class=\"ci\">[{m['m2_ci_low']:.4f}, {m['m2_ci_high']:.4f}]</td>"
            f"<td>{m['csl_n_tokens']}/{m['en_n_tokens']}</td></tr>"
        )
    parts.append("</tbody></table>")

    # Token-NLL heatmap (optional, from separate compute_m2 --token-nll run)
    if token_nll_file:
        p = Path(token_nll_file)
        if p.exists():
            try:
                tok_data = json.loads(p.read_text(encoding="utf-8"))
                if isinstance(tok_data, list) and tok_data:
                    m = tok_data[0]
                    parts.append("<h2>Per-token NLL heatmap</h2>")
                    parts.append(f"<p>File : {html.escape(m.get('file', ''))} "
                                 f" Model : {html.escape(m.get('model_name', ''))}</p>")

                    csl_tokens = m.get("csl_token_nll", [])
                    en_tokens  = m.get("en_token_nll", [])
                    max_nll = max(
                        [t["nll"] for t in csl_tokens + en_tokens if "nll" in t] or [0.0]
                    )
                    parts.append("<h3>CSL</h3>")
                    parts.append(render_heatmap_spans(csl_tokens, max_nll))
                    parts.append("<h3>EN paraphrase</h3>")
                    parts.append(render_heatmap_spans(en_tokens, max_nll))
            except Exception as e:
                parts.append(f"<p>[heatmap source unreadable: {html.escape(str(e))}]</p>")

    parts.append(
        "<footer>Generated by <code>scripts/m2_visualize.py</code>. "
        f"Thresholds from specs/15_M2_METRIC.csl §§ STRATIFIED. "
        "Color scale : green (low NLL, predictable) → red (high NLL, surprising).</footer>"
    )
    parts.append("</body></html>")
    return "".join(parts)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", help="m2_baseline.json OR per-run JSON")
    ap.add_argument("--out", default=None, help="output HTML path (default: alongside source)")
    ap.add_argument("--token-nll", default=None, dest="token_nll",
                    help="path to per-token NLL JSON (from compute_m2 --token-nll)")
    args = ap.parse_args()

    src = Path(args.source)
    if not src.exists():
        print(f"source not found: {src}", file=sys.stderr)
        return 2

    baseline = json.loads(src.read_text(encoding="utf-8"))
    html_text = render_report(baseline, args.token_nll)

    out_path = Path(args.out) if args.out else src.with_suffix(".html")
    out_path.write_text(html_text, encoding="utf-8")
    print(f"wrote {out_path} ({len(html_text):,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
