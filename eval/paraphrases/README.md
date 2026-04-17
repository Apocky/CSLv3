# T25 m₂ Paraphrase Corpus

Plain-text English renderings of each `eval/C*_CSL.csl` file for use
by the m₂ perplexity harness (`scripts/compute_m2.py`).

## Convention

A paraphrase is "what an **information-equivalent** English rendering
would say" — NOT a word-for-word translation, NOT a glyph-expansion.

### Must preserve

- **Facts** : every named entity, operation, constraint, invariant,
  test case, anti-pattern, and relationship from the CSL source.
- **Inferences permitted from the CSL** : if the CSL implies a fact
  through its structure (e.g. `x : i32` implies "x is a 32-bit
  integer"), the paraphrase must make that fact explicit.

### Must not

- Add facts not supported by the CSL.
- Strip facts even if they feel redundant (they're load-bearing
  for the paraphrase-quality check).
- Include Markdown syntax (headings, fences, lists with `*`).
  These pollute the m₂ measurement because they tokenize identically
  to structural English, biasing perplexity downward.

### Format

- UTF-8 plain text, `\n`-terminated lines.
- Prose paragraphs separated by blank lines.
- No fences, no bullet lists, no Markdown headings.
- Filename : `<corpus-id>.en` (e.g. `C1.en`, `C2.en`).

## Relationship to `eval/C*_EN.md`

The existing `C*_EN.md` files are the **pre-v1.0 m₁ source material**.
They contain Markdown headings + bullet lists that make them unsuitable
for direct perplexity comparison (the Markdown syntax tokens inflate
their token count without contributing semantic content).

The `.en` files in this directory are **derived** from those by :

1. Stripping Markdown headings (`#`, `##`, `###`).
2. Converting bullet lists into prose sentences.
3. Joining over-short lines into paragraphs.
4. Preserving every fact, operation, invariant, and entity.

The paraphrase-quality scorer (`scripts/m2_quality.py`) computes
embedding-cosine + entity-recall between `C*_CSL.csl` and its
paired `C*.en`. Scores below threshold flag for Apocky review.

## Quality gates

- embedding-cosine (sentence-transformers all-MiniLM-L6-v2) ≥ 0.70
- entity-recall (spaCy NER, both directions) ≥ 0.80
- flagged pairs require human review + CHANGELOG note

## License

Same as the parent project (MIT). Paraphrases are author-original prose.
