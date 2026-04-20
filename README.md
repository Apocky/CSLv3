# CSL — Caveman Spec Language

Formal notation and specification system for CSSL (Sigil). CSL provides a declarative grammar for expressing type systems, memory models, instruction sets, and compiler semantics.

Full documentation: **[cssl.dev/CSLv3.html](https://cssl.dev/CSLv3.html)**

---

## Overview

CSL is an ultra-dense specification notation designed for three-way readability: human spec authors, AI reasoning substrates, and compiler frontends. 74 Unicode glyphs + ASCII aliases, LL(2)-parseable, zero ambiguity.

- **Density = sovereignty** — every glyph earns its place
- **Three audiences** — humans, LLMs, and parser frontends all read the same source
- **Self-referential** — CSL specs are parsed and type-checked by the CSL parser itself

Current version: **v1.7.0**

## Syntax

CSL statements follow a fixed slot grammar:

```
[EVIDENCE?] [MODAL?] [DET?] SUBJECT [RELATION] OBJECT [GATE?] [SCOPE?] [META?]
```

### Core glyphs

| Glyph | Meaning |
|-------|---------|
| `§`   | section / declaration head |
| `W!`  | must (hard requirement) |
| `R!`  | reference (normative citation) |
| `N!`  | never / prohibition |
| `I>`  | intent / design rationale |
| `M?`  | may (optional) |
| `→`   | produces / maps to |
| `∀`   | for all |
| `∃`   | there exists |
| `∈`   | element of |
| `⊆`   | subset of |
| `≡`   | equivalent to |
| `✓`   | confirmed |
| `✗`   | refuted |
| `◐`   | partial evidence |

### Morpheme suffixes

`'d` (defined) `'f` (function) `'s` (set/sequence) `'t` (type) `'e` (effect) `'m` (module) `'p` (proof) `'g` (generic) `'r` (refinement)

### Compound operators

`. `(of/possessive) `+`(and) `-`(that-is) `⊗`(having) `@`(at/location)

## Usage

```sh
git clone https://github.com/Apocky/CSLv3.git
cd CSLv3

# Build the parser (requires Odin)
odin build parser/ -out:parser.exe

# Parse a spec file
./parser.exe specs/02_GRAMMAR.csl

# Type-check with diagnostics
./parser.exe --typecheck --json specs/02_GRAMMAR.csl

# Emit to multiple formats
./parser.exe --emit=markdown specs/02_GRAMMAR.csl
./parser.exe --emit=html     specs/02_GRAMMAR.csl
./parser.exe --emit=json     specs/02_GRAMMAR.csl
```

### Spec suite

| File | Content |
|------|---------|
| `specs/00_MANIFEST.csl` | Index and reading order |
| `specs/01_GLYPHS.csl`   | Full 74-glyph table + ASCII aliases |
| `specs/02_GRAMMAR.csl`  | LL(2) grammar, slot rules, BNF |
| `specs/03_MORPH.csl`    | Morpheme suffix system |
| `specs/04_SPATIAL.csl`  | Spatial / layout rules |
| `specs/05_REASON.csl`   | Reasoning and inference patterns |
| `specs/06_SPEC.csl`     | Meta-specification conventions |
| `specs/07_TYPESYS.csl`  | Type system and refinement types |
| `specs/08_COMPILER.csl` | Compiler semantics |
| `specs/09_BRIDGE.csl`   | Bridge to natural language |

## License

MIT — see [LICENSE](LICENSE).

The [PRIME_DIRECTIVE.md](PRIME_DIRECTIVE.md) is author-moral intent, not a license term.
