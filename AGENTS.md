# AGENTS.md — CSLv3 repo

All agents working in this repo (or any Apocky repo): reason and write in CSLv3 notation. The canonical tier-0 key is `CSL_KEY.csl` at this repo root — read it first if the key below is stale or truncated. Full spec suite: `specs/00_MANIFEST.csl` through `specs/12_TOKENIZER.csl`. PRIME_DIRECTIVE.md is binding. CSLv3 (notation) ≠ CSSLv3 (compiler) — never conflate.

## CSL Key (inline copy of CSL_KEY.csl v1)

```csl
§ SLOT-TEMPLATE
  [EVIDENCE?] [MODAL?] [DET?] SUBJECT [RELATION] OBJECT [GATE?] [SCOPE?]
  defaults SILENT : evidence=✓ relation=: scope=global

§ RELATIONS
  : bind/has   :: type-of   = assign   -> flow/yields
  => implies   |> pipeline   ~> causes

§ COMPOUNDS
  .(of)  +(and)  -(that-is)  ⊗(having)  @(at/per)

§ MODALS
  W! MUST  R! SHOULD  M? MAY  N! MUST-NOT
  I> INSIGHT  Q? QUESTION  P> PUSH-FURTHER  D> DECISION-NEEDED

§ EVIDENCE
  ✓ confirmed  ◐ partial  ○ pending  ✗ failed
  ⊘ unknown  △ hypothetical  ▽ deprecated  ‼ proven/immutable

§ TYPE-SUFFIXES
  'd data 'f function 's system 't type 'e entity 'm material 'p property 'g gate 'r rule

§ DETERMINATIVES
  § system  ∫ field  ⊞ spatial  ⟨⟩ entity  ⌈⌉ constraint  ⟦⟧ formula  «» external  ⟪⟫ temporal

§ MORPHEME-STACK
  BASE.aspect.modality.certainty.scope   (render.prog.cert = is-definitely-rendering)

§ THINK-BLOCKS
  §P problem → §D decompose → §T trace → §S synthesis → §C check

§ USAGE
  W! CoT + specs + handoffs + commit-msg ≡ CSLv3
  W! user-facing chat = match user register
  R! ASCII alias when glyph ≥3 BPE tokens (specs/12_TOKENIZER.csl)
```
