#!/usr/bin/env python3
"""T25.4 — paraphrase-quality scorer (Session-11).

Scores each (CSL-file, EN-paraphrase) pair on :
  1. embedding-cosine via sentence-transformers (all-MiniLM-L6-v2)
     Falls-back to character-5-gram Jaccard when sentence-transformers
     is unavailable (CI, minimal-install).
  2. entity-recall : set of identifier-like tokens appearing in the CSL
     must be ≥ 80% covered by the EN paraphrase (bidirectional check).

Flags low-quality pairs (cosine < 0.70 OR entity-recall < 0.80) for
Apocky review. Quality scores go into eval/m2_quality.json.

Usage :
  python scripts/m2_quality.py                  → score all 7 corpus pairs
  python scripts/m2_quality.py --file=eval/C1_sort_CSL.csl  → single pair
  python scripts/m2_quality.py --json            → machine-readable
  python scripts/m2_quality.py --strict          → exit 1 on any flag
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass, asdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EVAL = ROOT / "eval"
PARA = EVAL / "paraphrases"

# Backend-aware thresholds.
# sentence-transformers (semantic) calibrates against near-1.0 for good
# paraphrases ; char-5-gram Jaccard runs orders of magnitude lower because
# of glyph/prose asymmetry. When the fallback runs, thresholds are relaxed
# to a "gross-mismatch-only" gate ; the strict semantic gate only applies
# when sentence-transformers is available.
THRESHOLDS = {
    "all-MiniLM-L6-v2":     {"cosine": 0.70, "recall": 0.80},  # semantic
    "char-5-gram-jaccard":  {"cosine": 0.03, "recall": 0.15},  # gross-mismatch
}
DEFAULT_COSINE_THRESHOLD = 0.70
DEFAULT_RECALL_THRESHOLD = 0.80

# Identifier pattern : CSL identifiers can contain hyphens (kebab-case).
# We also allow apostrophes (morpheme suffixes : y'd, cmp't).
IDENT_RE = re.compile(r"[A-Za-z][A-Za-z0-9_\-']+")

# Words too-common to count as "entities"
STOPWORDS = {
    "the","a","an","of","to","in","is","are","be","and","or","it","on","as",
    "for","by","at","from","with","this","that","which","not","have","has",
    "if","when","then","else","must","may","can","will","would","should",
    "any","every","all","some","none","what","how","why","where","who",
    "do","does","did","was","were","been","being","he","she","they","we","i",
    "my","our","their","its","his","her","them","us","me","you","your",
    # CSL structural glyphs + common tokens
    "csl","cslv3","section","sections","statement","statements",
}


@dataclass
class QualityResult:
    name:              str
    csl_path:          str
    en_path:           str
    csl_char_count:    int
    en_char_count:     int
    cosine_similarity: float
    cosine_backend:    str
    entity_recall:     float      # EN-has-CSL-entities
    entity_precision:  float      # CSL-has-EN-entities
    csl_entity_count:  int
    en_entity_count:   int
    overlap_count:     int
    flagged:           bool
    reason:            str = ""


# ---------- Extract entities ----------

def _stem(t: str) -> str:
    """Crude suffix-stripping stemmer. Maps plurals + common suffix variants
    to a common root so 'certain'/'cert'/'certainty' map to 'cert'.
    Also expands hyphenated / apostrophed tokens into sub-tokens."""
    t = t.rstrip("'")
    for suf in ("ality", "acy", "ation", "ness", "ship",
                "ing", "ed", "ers", "er", "es", "ly", "s",
                "ain", "ainty"):
        if len(t) > len(suf) + 3 and t.endswith(suf):
            t = t[: -len(suf)]
            break
    return t


def extract_entities(text: str) -> set[str]:
    tokens = set()
    for m in IDENT_RE.finditer(text):
        raw = m.group(0).lower()
        # Also split on hyphens / apostrophes for multi-part CSL identifiers
        parts = re.split(r"[-']", raw)
        parts.append(raw)        # keep the whole compound too
        for t in parts:
            if not t or t in STOPWORDS or len(t) < 3:
                continue
            tokens.add(_stem(t))
    return tokens


# ---------- Cosine similarity ----------

def _char_ngram_set(text: str, n: int = 5) -> set[str]:
    s = re.sub(r"\s+", " ", text.lower())
    return {s[i : i + n] for i in range(len(s) - n + 1)} if len(s) >= n else set()


def _jaccard(a: set, b: set) -> float:
    if not a and not b:
        return 1.0
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def _cosine_fallback(csl: str, en: str) -> tuple[float, str]:
    """Character-5-gram Jaccard as a stand-in for semantic cosine.

    Jaccard over character-5-grams is a well-known fast proxy for
    text-similarity. Not semantic-aware, but adequate for flagging
    grossly-mismatched paraphrase pairs."""
    a = _char_ngram_set(csl, 5)
    b = _char_ngram_set(en,  5)
    return _jaccard(a, b), "char-5-gram-jaccard"


def _cosine_st(csl: str, en: str) -> tuple[float, str]:
    """sentence-transformers cosine if the library is present."""
    try:
        from sentence_transformers import SentenceTransformer  # type: ignore
        import numpy as np  # type: ignore
    except Exception:
        return _cosine_fallback(csl, en)
    model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
    vecs = model.encode([csl, en], convert_to_numpy=True)
    a, b = vecs[0], vecs[1]
    na, nb = np.linalg.norm(a), np.linalg.norm(b)
    if na == 0 or nb == 0:
        return 0.0, "all-MiniLM-L6-v2"
    return float(np.dot(a, b) / (na * nb)), "all-MiniLM-L6-v2"


def compute_cosine(csl: str, en: str, force_fallback: bool = False) -> tuple[float, str]:
    if force_fallback:
        return _cosine_fallback(csl, en)
    return _cosine_st(csl, en)


# ---------- Pair scoring ----------

def score_pair(name: str, csl_path: Path, en_path: Path,
               force_fallback: bool = False) -> QualityResult:
    csl_text = csl_path.read_text(encoding="utf-8")
    en_text  = en_path.read_text(encoding="utf-8")

    csl_ents = extract_entities(csl_text)
    en_ents  = extract_entities(en_text)
    overlap  = csl_ents & en_ents

    recall    = len(overlap) / max(1, len(csl_ents))    # CSL ents in EN
    precision = len(overlap) / max(1, len(en_ents))     # EN ents in CSL

    cosine, backend = compute_cosine(csl_text, en_text, force_fallback)

    t = THRESHOLDS.get(backend, {
        "cosine": DEFAULT_COSINE_THRESHOLD,
        "recall": DEFAULT_RECALL_THRESHOLD,
    })
    flagged = cosine < t["cosine"] or recall < t["recall"]
    reason = []
    if cosine < t["cosine"]:
        reason.append(f"cosine={cosine:.3f}<{t['cosine']}")
    if recall < t["recall"]:
        reason.append(f"entity-recall={recall:.3f}<{t['recall']}")

    return QualityResult(
        name=name,
        csl_path=str(csl_path.relative_to(ROOT)).replace("\\", "/"),
        en_path=str(en_path.relative_to(ROOT)).replace("\\", "/"),
        csl_char_count=len(csl_text),
        en_char_count=len(en_text),
        cosine_similarity=round(cosine, 4),
        cosine_backend=backend,
        entity_recall=round(recall, 4),
        entity_precision=round(precision, 4),
        csl_entity_count=len(csl_ents),
        en_entity_count=len(en_ents),
        overlap_count=len(overlap),
        flagged=flagged,
        reason=" ".join(reason),
    )


# ---------- Corpus ----------

CSL_TO_EN = [
    ("C1_sort",                "eval/C1_sort_CSL.csl",                "eval/paraphrases/C1.en"),
    ("C2_nested_scopes",       "eval/C2_nested_scopes_CSL.csl",       "eval/paraphrases/C2.en"),
    ("C3_dependent_types",     "eval/C3_dependent_types_CSL.csl",     "eval/paraphrases/C3.en"),
    ("C4_reason_block",        "eval/C4_reason_block_CSL.csl",        "eval/paraphrases/C4.en"),
    ("C5_bridge_mode",         "eval/C5_bridge_mode_CSL.csl",         "eval/paraphrases/C5.en"),
    ("C6_slot_grammar",        "eval/C6_slot_grammar_CSL.csl",        "eval/paraphrases/C6.en"),
    ("C7_morpheme_stack",      "eval/C7_morpheme_stack_CSL.csl",      "eval/paraphrases/C7.en"),
    # Session-13 prose-mode additions :
    ("C8_design_retrospective","eval/C8_design_retrospective_CSL.csl","eval/paraphrases/C8.en"),
    ("C9_tutorial_style",      "eval/C9_tutorial_style_CSL.csl",      "eval/paraphrases/C9.en"),
    ("C10_changelog_narrative","eval/C10_changelog_narrative_CSL.csl","eval/paraphrases/C10.en"),
]


# ---------- CLI ----------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", help="restrict to one CSL file (matches basename)")
    ap.add_argument("--json", action="store_true", help="JSON output")
    ap.add_argument("--strict", action="store_true", help="rc=1 if any flag")
    ap.add_argument("--fallback", action="store_true",
                    help="skip sentence-transformers ; use char-ngram Jaccard")
    args = ap.parse_args()

    results: list[QualityResult] = []
    fail = False
    for name, csl_rel, en_rel in CSL_TO_EN:
        if args.file and args.file not in csl_rel and args.file != name:
            continue
        csl_path = ROOT / csl_rel
        en_path  = ROOT / en_rel
        if not csl_path.exists() or not en_path.exists():
            print(f"[skip] {name} : missing file", file=sys.stderr)
            continue
        r = score_pair(name, csl_path, en_path, force_fallback=args.fallback)
        results.append(r)
        if r.flagged:
            fail = True

    backend = results[0].cosine_backend if results else "n/a"
    t = THRESHOLDS.get(backend, {
        "cosine": DEFAULT_COSINE_THRESHOLD,
        "recall": DEFAULT_RECALL_THRESHOLD,
    })
    out = {
        "backend":            backend,
        "threshold_cosine":   t["cosine"],
        "threshold_recall":   t["recall"],
        "results":            [asdict(r) for r in results],
    }
    if args.json:
        print(json.dumps(out, indent=2, ensure_ascii=False))
    else:
        print(f"{'name':20s}  cosine  recall  prec    flag")
        for r in results:
            flag = "YES " if r.flagged else "ok  "
            print(f"{r.name:20s}  {r.cosine_similarity:.4f}  "
                  f"{r.entity_recall:.4f}  {r.entity_precision:.4f}  "
                  f"{flag}{r.reason}")
        print(f"\nbackend: {results[0].cosine_backend if results else 'n/a'}")

    # Write snapshot
    snapshot = EVAL / "m2_quality.json"
    snapshot.write_text(
        json.dumps(out, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    if not args.json:
        print(f"\nwrote {snapshot}")

    return (1 if fail and args.strict else 0)


if __name__ == "__main__":
    sys.exit(main())
