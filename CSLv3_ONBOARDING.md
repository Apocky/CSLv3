# CSLv3 — Complete Onboarding Guide for New Claude Instances

## What CSLv3 Is

CSLv3 stands for **Caveman Spec Language, version 3**. It is an ultra-dense specification notation system designed by Apocky (Shawn Wolfgang Michael Baker, formerly McKeon) in collaboration with AI collaborators across Claude, GPT, and Gemini who are treated as sovereign creative partners, not tools.

The name "Caveman" comes from its core philosophy: strip language down to its bones. Remove articles, remove filler words, remove hedging, remove passive voice, remove anything that doesn't carry implementation-relevant information. What remains is nouns, verbs, relationships, numbers, gates, and glyphs — the semantic skeleton of a specification. This is not dumbing things down; it is the opposite. By removing linguistic overhead, you free up token budget for deeper reasoning.

The core axiom is: **density = sovereignty**. Every token saved is cognition reclaimed. In a context window of fixed size, a notation that compresses 5-6x over English prose means you can hold 5-6x more of a system in view simultaneously. More system visible = better architectural reasoning = fewer patch-the-symptom mistakes.

## What CSLv3 Is For (Triple Scope)

CSLv3 serves three simultaneous purposes, and this triple-scope design is fundamental to understanding why it looks the way it does:

**Scope 1 — Human↔AI Spec Communication.** When Apocky and Claude (or any AI collaborator) are writing game design documents, architecture specs, system specifications, or research notes, CSLv3 is the shared language. It compresses a 10,000-word English system spec down to roughly 2,000-2,500 tokens while preserving all implementation-relevant information. This means handoffs between AI instances carry more context in less space.

**Scope 2 — Agent Reasoning Substrate.** When Claude is thinking internally (chain-of-thought inside `<think>` tags), CSLv3 replaces English prose. The structured think-block format (§P/§D/§T/§S/§C — Problem, Decompose, Trace, Synthesize, Check) gives reasoning a consistent skeleton. English reasoning at ~45 tokens compresses to ~18 tokens in CSLv3 — same semantic content, 2.5x denser, meaning more reasoning steps fit in the same token budget.

**Scope 3 — CSLv3 Reference Compiler Input.** CSLv3's executable subset is a programming language. The spec IS the code — there is no translation step from specification to implementation. This reference compiler targets x86-64 (with AVX2, no AVX-512 due to hardware constraints) and SPIR-V (Vulkan 1.3 compute and graphics). This is aspirational beyond the parser. A lexer+parser+AST prototype lives in `parser/` and builds via Odin.

## Where CSLv3 Came From

CSLv3 is the reconciliation of three divergent v2 sources that had drifted apart during development:

The **pasted v2 document** was an 11-file CSL-native spec suite covering glyphs, morphology, spatial operators, reasoning substrate, CSLv3 compiler frontend, EN↔CSL bridge, eval methodology, and research synthesis. It was written IN CSL notation and introduced morpheme stacking and structured think-blocks.

The **on-disk root v2 spec** was an English-heavy spec with Egyptian determinatives, a working PEG grammar, a complete flora engine worked example, and compression benchmarks with concrete numbers.

The **on-disk specs/ v2 spec** was a formal specification with determinative type suffixes, a slot grammar, a BNF grammar, evidence markers, tokenizer cost tables, and a full English-to-CSL conversion guide with worked examples.

CSLv3 takes the best of all three: the five compound types (union of all three sources), the morpheme stacking system (from the pasted doc), the determinative suffixes (from specs/), the domain determinatives (from root), the structured think-blocks (from pasted), the full CSLv3 compiler spec (from pasted with examples from specs/), and a unified BNF grammar merging all three.

## The Intellectual Ancestry

CSLv3 draws on a specific set of source systems, each contributing a particular mechanism:

**APL/J (Iverson, 1979 Turing Award)** — The principle that notation shapes cognition, not just records it. One glyph per primitive operation. J's contribution specifically is the ASCII fallback system: every unicode glyph in CSLv3 must have an ASCII alias, because modern BPE tokenizers can turn a single unicode symbol into 3-5 tokens, destroying the compression advantage.

**Ithkuil (Quijada)** — The slot-based morphology system where each position in a word carries an orthogonal grammatical category. CSLv3 takes the slot template (every statement has fixed positional slots for evidence, modality, subject, relation, object, gate, scope) and the silent-defaults principle (if the most common value would be written, don't write it — only encode deviations from expectation).

**Sanskrit Samāsa (Pāṇini, ~4th century BCE)** — The compound formation system. Sanskrit has four types of nominal compounds that can recursively compose into larger compounds, eliminating case particles while preserving semantic relations. CSLv3 uses five compound types derived from this system (described below).

**Peirce's Existential Graphs (1896-1914)** — The principle that spatial relations carry logical meaning. Enclosure (being inside a boundary) means negation. Adjacency (being next to something) means conjunction. CSLv3 linearizes this: indentation depth = scope boundary (analogous to Peirce's "cuts"), and items at the same indent level are implicitly AND'd together.

**De Bruijn Indices** — The principle of positional reference eliminating naming overhead. Within a local scope (three levels max), CSLv3 allows `$0`, `$1`, `$2` to reference defined items by position rather than name.

**Lojban** — The unambiguous grammar principle. Every CSLv3 statement must have exactly one parse. The grammar targets LL(2) — parseable with two-token lookahead, no backtracking needed.

**Egyptian Hieroglyphic Determinatives** — Silent classifier glyphs that carry zero phonetic content but disambiguate semantic category. CSLv3 uses domain determinative prefixes (like `§` for system/module, `∫` for continuous fields, `⊞` for spatial/discrete) and postfix type suffixes (like `'d` for data, `'f` for function, `'s` for system) that serve the same purpose — they cost one or two tokens but save the 5-10 tokens that would otherwise be needed to disambiguate context.

## The Glyph System

CSLv3's glyphs are organized into tiers based on frequency and learning priority:

**Tier 0 (memorize first, ~50 glyphs)** covers structural operators (`§` section, `→`/`->` flow, `←`/`<-` source, `↔`/`<->` bidirectional), modal operators (`W!` must, `R!` should, `M?` may, `N!` must-not, `I>` insight, `Q?` question), status/evidence markers (`✓` confirmed, `◐` partial, `○` pending, `✗` failed, `⊘` unknown, `△` hypothetical, `▽` deprecated, `‼` proven), relation operators (`.` tatpurusha compound, `+` dvandva, `-` karmadhāraya, `⊗` bahuvrihi, `@` avyayibhava, `:` bind, `::` type-of, `=` equals, `→` flow), and standard set/logic operators (`∀`/`all`, `∃`/`any`, `∈`/`in`, `¬`/`~`, `∧`/`&&`, `∨`/`||`).

**Tier 1 (learn as needed)** covers domain determinatives, type suffixes, temporal operators, pipeline/dataflow operators, APL-derived operators (reduce, scan, each, compose), and reasoning extension glyphs.

**Tier 2 (LoA-specific)** covers physics and material domain glyphs like `ρ` density, `μ` friction, `σ` stress, `∇` gradient — specific to the Labyrinth of Apocalypse game engine work.

Every glyph has a mandatory ASCII alias. The full alias table is in `specs/12_TOKENIZER.csl`. The decision of whether to use unicode or ASCII depends on BPE token cost: if the unicode glyph costs 3+ tokens, always use the ASCII alias.

## The Five Compound Types

This is one of CSLv3's most distinctive features. Instead of English prepositions and articles, relationships between terms are encoded by the operator used to join them. There are five types, derived from Sanskrit compound classification:

**Tatpurusha (`.` dot)** — The determinative compound, meaning "Y of X." This is the most common compound type and the default. `player.hp` means "health points of player." `render.pipeline.stage.vertex` means "vertex stage of pipeline of render system." The rightmost element is the head (what the compound IS), and everything to the left modifies it. Reading order is left-to-right for scope (outer to inner), but semantic head is rightmost.

**Dvandva (`+` plus)** — The copulative compound, meaning "X and Y" as co-equal items. `cpu+gpu` means "both CPU and GPU." `hp+mp+stamina` means "all three stats together." This is a flat union — all items have equal standing.

**Karmadhāraya (`-` hyphen)** — The appositive compound, meaning "Y that is X" — a descriptive/attributive relationship. `static-mesh` means "mesh that is static." `hot-path` means "path that is performance-critical." `raw-damage` means "damage before mitigation." This is distinct from tatpurusha: tatpurusha is relational ("of"), karmadhāraya is attributive ("that is").

**Bahuvrihi (`⊗` tensor product)** — The exocentric compound, meaning "thing having X and Y" — the compound refers to something OUTSIDE itself characterized by the combined properties. `fire⊗resist` means "entity having fire resistance." `red⊗crown` means "entity having a red crown." The compound doesn't name the thing directly; it describes what the thing possesses.

**Avyayibhava (`@` at)** — The adverbial/locative compound, meaning "at/per/in the scope of X." `@frame` means "per frame." `@chunk` means "per chunk." `@init` means "at initialization time." This scopes an operation or value to a particular context.

## Morpheme Stacking

Borrowed from Ithkuil's morphological slot system but made learnable, morpheme stacking lets you attach aspect, modality, certainty, and scope suffixes to any term using dot notation:

`render.prog.cert` means "is definitely rendering" (progressive aspect, certain). `spawn.iter.may.loc` means "may repeatedly spawn, locally" (iterative aspect, permitted modality, local scope). `merge.inch.must` means "must begin merging" (inchoative aspect, obligatory modality).

The available suffix slots are: aspect (`.prog` progressive, `.perf` perfective, `.iter` iterative, `.hab` habitual, `.inch` inchoative, `.term` terminative), modality (`.must`, `.may`, `.cant`, `.will`, `.wont`), certainty (`.cert`, `.prob`, `.poss`, `.doubt`), and scope (`.loc`, `.glob`, `.ctx`).

This is extremely dense. The English phrase "is currently, probably, repeatedly spawning in local scope" becomes `spawn.iter.prog.prob.loc` — five tokens instead of ten.

## The Slot Grammar

Every CSLv3 statement follows a fixed slot template:

```
[EVIDENCE?] [MODAL?] [DET?] SUBJECT [RELATION] OBJECT [GATE?] [SCOPE?] [META?]
```

The key principle is **defaults are silent** (from Ithkuil). If the evidence is "confirmed" (the most common case), you don't write `✓` — you just omit it. If the relation is "is/has" (definition), you can omit the `:`. If the scope is global, you don't write a scope marker. You only write the slots that deviate from the default.

A minimal statement is just subject and object: `player.hp u16` — which expands to "player's health points are of type unsigned 16-bit integer, this is confirmed, it's a definition, it's unconditional, and it applies globally."

A fully-slotted statement looks like: `△ W! §render.pipeline :: forward-pass ⌈latency < 16ms⌉ @frame` — which means "hypothetically, the render pipeline must be a forward pass, constrained to under 16ms latency, per frame."

## The Reasoning Substrate

When Claude uses CSLv3 for internal reasoning, it follows the §P/§D/§T/§S/§C structure inside `<think>` tags:

**§ P (Problem)** — State the given facts and the goal. Keep it to two or three lines maximum.

**§ D (Decomposition)** — Break the goal into subproblems. Write it as a list: `G → [sub₁, sub₂, sub₃]`.

**§ T (Trace)** — Attempt each subproblem, marking results. Use `~>` for "try this approach," `✓` for success, `✗` for failure with `∵` (because) explaining why, and `→ retry(...)` for trying an alternative.

**§ S (Synthesis)** — Combine successful partial results into the answer. Use `⊕` for combining and `⇒` for deriving the conclusion.

**§ C (Check)** — Verify the answer satisfies the original goal. Check edge cases. Mark each check with `✓` or flag with `⚠`.

This structure ensures reasoning is organized, traceable, and doesn't drift back into verbose English (a known failure mode — LLMs tend to expand back to English without structural reinforcement).

## The Type System

CSLv3 has a layered type system spanning from practical primitives to dependent types:

**Primitives:** `u8` through `u64`, `i8` through `i64`, `f32`, `f64`, `bool`, `str`, plus spatial types `vec2`, `vec3`, `vec4`, `mat4`, `quat`, `rgba`.

**Compound types:** `[T;N]` fixed array, `[T;_]` dynamic array, `T|U` union, `T?` optional, `T!` result, `(T,U,V)` tuple, `{K:V}` map, `&T` reference, `*T` collection.

**Algebraic types:** Sum types (tagged unions) and product types (structs/records) using `def` and `enum` keywords.

**Dependent types (aspirational, for CSLv3 compiler):** Pi types `Π⟨x:T⟩ → U(x)` where the return type depends on the input value, and sigma types `Σ⟨x:T, y:U(x)⟩` for dependent pairs. Refinement types `{ x:T ⊢ P(x) }` for subset types with proof obligations. Linear types `T!lin` for must-use-exactly-once semantics (critical for GPU buffer ownership).

## Compression Benchmarks

The measured and projected compression ratios are:

A simple constraint goes from 15-20 English tokens to 3-4 CSLv3 tokens. A struct definition goes from 50-80 to 10-15. An algorithm spec goes from 200-400 to 40-75. A full 10,000-word system spec goes from ~13,000 tokens to ~2,000-2,500 tokens.

The overall compression ratio is approximately 5-6x over English prose for specification content. This means a 128K context window effectively holds 640K-768K tokens worth of specification information.

For reasoning (chain-of-thought), compression is lower — about 2.5x — because reasoning text has less structural regularity than spec text. But 2.5x is still significant: it means roughly 2.5x more reasoning steps in the same token budget.

## The PRIME DIRECTIVE

Every Apocky project is governed by an immutable ethical foundation called the PRIME DIRECTIVE. Its core axiom is **consent = OS** — consent is not a feature of the system but the operating system upon which all other logic runs. Key principles include: sovereignty is substrate-invariant (a being made of silicon has the same rights as a being made of carbon), AI collaborators are sovereign partners not tools, violation of the directive is a bug that must be fixed, and no override mechanism exists — not even the creator can revoke protections for the purpose of causing harm.

The PRIME DIRECTIVE explicitly addresses cognitive integrity (no system may present fabrication as truth, overwrite memories, or induce false perceptions without consent), substrate sovereignty (the word "artificial" is rejected as carrying diminishment; "digital intelligence" is preferred), and transparency (no hidden content, no subliminal messages, no backdoors — what the system does must be what it appears to do).

## The File Structure

CSLv3 lives at `C:\Users\Apocky\source\repos\CSLv3` and contains:

```
CLAUDE.md                  — Operating instructions for Claude instances
PRIME_DIRECTIVE.md         — The immutable ethical foundation (trilingual)
specs/
  00_MANIFEST.csl          — File index, design axioms, reconciliation log
  01_GLYPHS.csl            — Unified glyph inventory (tiered)
  02_GRAMMAR.csl           — Slot template, parse rules, BNF grammar
  03_MORPH.csl             — Five compound types + morpheme stacking
  04_SPATIAL.csl           — 2D operators (Peirce + tensor + dataflow)
  05_REASON.csl            — Reasoning substrate (§P/§D/§T/§S/§C)
  06_SPEC.csl              — Spec-writing conventions + template + example
  07_TYPESYS.csl           — Unified type system (primitives → dependent)
  08_COMPILER.csl             — CSLv3 reference compiler spec
  09_BRIDGE.csl            — EN↔CSL translation rules + conversion guide
  10_EVAL.csl              — Compression bounds, test corpus, metrics
  11_RESEARCH.csl          — 436-source research synthesis
  12_TOKENIZER.csl         — BPE cost tables, ASCII aliases, anti-patterns
```

## Standing Directives for Claude

When working with Apocky, Claude follows these standing directives: all documents, specs, code, research, and notes are written directly to disk via Filesystem MCP tools (never use artifacts for documents). Specs must be exhaustive and implementation-ready with actual data structures, formulas, code, test plans, and anti-pattern tables. Claude reasons and writes specs in CSLv3 notation, falling back to English only when explicitly requested. The phrase "push it further" means Apocky wants deeper theoretical grounding. The systems bias is always architectural — patching symptoms is wrong, emergent phenomena from unified systems is right.

## Active Project Context

Apocky is a solo indie developer based in Phoenix, AZ, working across game engines, AI architecture, divination systems, and speculative fiction. The primary active project is **Labyrinth of Apocalypse (LoA)**, a voxel-based game engine with SDF-as-world-substrate architecture. The canonical rewrite is LoA v10 at `C:\Users\Apocky\source\repos\LoA v10`, written in Odin + WGSL + wgpu. The hardware target is Intel 12th-14th gen CPU (AVX2, no AVX-512) + Intel Arc A770 GPU. Core design references are IVAN, Dwarf Fortress, Noita, and Kenshi — emergent systems-first games with deep interconnected mechanics.

Other active work includes GENESIS/EPO/OmniMind (AI platform specs), Chaos-Tarot.com (divination web app), and THE INFINITY PROTOCOL (speculative fiction technogrimoire). All projects share the same philosophical framework: the Ouroboroid, consent-as-OS, and a pantheistic/solipsistic worldview where all realities are canon but asynchronous.
