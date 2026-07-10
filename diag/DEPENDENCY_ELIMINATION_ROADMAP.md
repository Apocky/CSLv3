§ CSLv3 DEPENDENCY-AUDIT + BESPOKE-REPLACEMENT ROADMAP
  generated_at : 2026-04-17 ← Session 13 research-deliverable
  author       : Apocky + AI-collaborator
  status       : ◐ research-draft ← awaiting Apocky-prioritization
  scope        : CSLv3 v1.1.0 @ tree-date

═════════════════════════════════════════════════════════════════════════
§ MOTIVATION                                                             ⟦⟧
═════════════════════════════════════════════════════════════════════════

I> density = sovereignty ← applies to-tooling also
I> v1.0 shipped w/ external-dependencies ← pragmatic bootstrap
I> post-v1.1.0 : reduce + eventually-eliminate external-dependencies
I> mirrors CSSLv3 no-LLVM commitment ← bespoke-everything eventual-state
I> "all-external-dependencies" @ widest-reading ⊆ goal

§§ CORE-PRINCIPLE
  ∀ dependency d ∈ tree :
    E(d) = maintenance-cost + portability-risk + supply-chain-risk + version-drift
    V(d) = functionality-delivered + time-saved + community-support
    ROI(d) = V(d) / E(d)
  replace d iff bespoke-alternative(d) yields higher-ROI within-budget
  W! "budget" = Apocky-time + computational-hours ¬ calendar-weeks

§§ ADJACENT-CONSTRAINT
  v1.0+ STABILITY ← external-user-visible surfaces frozen
  ∴ replacements must-be drop-in ← same behavior • same protocol • same output
  ∴ implementation-swap ≠ breaking-change ← additive-only

═════════════════════════════════════════════════════════════════════════
§ COMPLETE DEPENDENCY INVENTORY                                          ⊞
═════════════════════════════════════════════════════════════════════════

§§ LAYER-1 : PARSER (Odin) — minimal-dependency baseline

  D01 Odin compiler                 toolchain  • required-to-build parser.exe
      ↳ LLVM-backend under-hood     ← LLVM is-transitive-dependency
  D02 Odin stdlib                   runtime    • strings, fmt, os, path, time
  D03 MSVC / mingw-w64 linker       toolchain  • Windows linker (CRT)

§§ LAYER-2 : LSP SERVER (Rust) — heaviest-dep-density in-tree

  D04 Rust toolchain (rustc + cargo)      toolchain    • self-hosted
      ↳ LLVM-backend under-hood           ← transitive
  D05 tower-lsp                            async-lsp    • LSP framework
  D06 tokio                                runtime      • async runtime (large)
  D07 tower                                abstraction  • service trait
  D08 lsp-types                            types        • LSP v3.17 types
  D09 rusqlite + libsqlite3-sys            storage      • SQLite C-lib binding
  D10 serde + serde_json                   serialization• ubiquitous in ecosystem
  D11 blake3                               crypto-hash  • fast + secure
  D12 tracing + tracing-subscriber         observability• structured-logging
  D13 regex + regex-automata               text-match   • RE2 algorithm
  D14 levenshtein                          string-dist  • ~10 LOC algorithm
  D15 async-trait + futures + pin-project  async-ergo   • trait-generics helpers
  D16 anyhow + thiserror                   errors       • idiomatic rust-errors
  D17 url                                  uri-parsing  • LSP uses URI format
  D18 percent-encoding + form-urlencoded   uri-parsing  • URI-dependency
  D19 idna + icu-{normalizer,properties,collections}  unicode  • huge-stack
  D20 regex-syntax                         regex-engine • dependency of-regex
  D21 parking_lot                          concurrency  • faster-Mutex
  D22 dashmap                              concurrency  • lock-free HashMap
  D23 socket2 + mio                        networking   • lower-level (via tokio)
  D24 bitflags                             utility      • common macro
  D25 hashbrown                            collections  • Swiss-table HashMap
  D26 getrandom                            crypto-rng   • OS-entropy source
  D27 arrayref + arrayvec                  utility      • stack-collections
  D28 tempfile                             utility      • mkstemp-equiv
  D29 (50+ transitive deps)                ecosystem    • proc-macro2/quote/syn/...

§§ LAYER-3 : VSCODE CLIENT (TypeScript)

  D30 Visual Studio Code (editor)          editor       • MS proprietary
  D31 TypeScript compiler                  toolchain    • MS open-source
  D32 vscode-languageclient                npm-pkg      • MS LSP-client
  D33 Node.js (for tsc)                    runtime      • JS-runtime

§§ LAYER-4 : SMT VALIDATION

  D34 Z3 4.16.0 (binary)                   solver       • Microsoft Research
      ↳ 40+ MB binary • C++ + LLVM-built   ← external-executable
  D35 CVC5 1.3.3 (binary)                  solver       • Stanford + Iowa
      ↳ similar-scale + C++ build           ← external-executable
  D36 SMT-LIB2 text-protocol               protocol     • bespoke in-tree

§§ LAYER-5 : m₂ PERPLEXITY (Python + llama.cpp)

  D37 Python 3.14 interpreter              runtime      • CPython or-equivalent
  D38 llama-perplexity.exe                 binary       • from llama.cpp tree
      ↳ llama.cpp C++ + ggml + cuBLAS/Vulkan ← giant
  D39 GGUF model-files ×3                  data         • ~7 GB model-weights
      ↳ Qwen2.5 + Llama-3.2 + Mistral-7B
  D40 cryptography                         crypto       • Ed25519 + AES etc.
  D41 sentence-transformers (OPTIONAL)     ML           • embedding-models
      ↳ torch + transformers + huggingface ← huge-stack
  D42 jsonschema                           validation   • JSON-Schema verifier
  D43 pandoc (OPTIONAL)                    doc-convert  • Haskell-built
  D44 html5lib (OPTIONAL)                  html-parse   • W3C parser
  D45 latexmk (OPTIONAL)                   build-driver • TeXLive-family

§§ LAYER-6 : BUILD + CI + RELEASE

  D46 bash (Git-for-Windows or-equiv)      shell        • release.sh runner
  D47 git                                  vcs          • tag + commit
  D48 GNU coreutils (cp + mv + sha256sum)  tools        • cross-platform nits
  D49 OpenSSL / bcrypt (transitive)        crypto       • via Python-cryptography

§§ TOTAL-SURFACE
  declared : ~20 primary dependencies
  transitive: ~200+ dependencies
  attack-surface : wide
  supply-chain-risk : high (cargo + npm + pypi all-historically-compromised)
  portability : Windows-first ← Linux+macOS need-per-platform work

═════════════════════════════════════════════════════════════════════════
§ CLI-BACKEND LIMITATIONS (SHORE-UP ANALYSIS)                          ◐
═════════════════════════════════════════════════════════════════════════

§§ SESSION-12 PIVOT CONTEXT
  llama-cpp-python unavailable @ Python-3.14 ← Python-binding wheel-gap
  fallback : subprocess → llama-perplexity.exe
  ratio-unbiased ← m₂ = NLL(CSL)/NLL(EN) both-runs-same-backend
  ∴ infrastructure-correct • absolute-NLL biased

§§ LIMITATION INVENTORY

  L1 ⊘ per-token NLL NOT-captured
     cause    : llama-perplexity.exe emits chunk-level-aggregate only
     impact   : visualization-heatmap degraded ← per-chunk not-per-token
     severity : MEDIUM ← visualization-only • m₂ ratio unaffected
     fix-path :
       F1a : switch to llama-cli --log-probs ← emits per-token
       F1b : C-FFI to llama.cpp directly (Odin + llama.h)
       F1c : Python-3.13 fallback + llama-cpp-python
       F1d : bespoke-inference (long-term • Layer-5-elimination)

  L2 ⊘ repeat-pad introduces absolute-NLL BIAS
     cause    : short-fixtures padded-to-128-tokens via repetition
     impact   : chunks-2+ get KV-cache-advantage ← absolute-NLL lower
     severity : LOW ← ratio-unbiased • only absolute reporting affected
     fix-path :
       F2a : use real-pad (whitespace or EOS) instead-of repeat
       F2b : drop-pad + accept single-chunk CI-width
       F2c : aggregate corpus-level ← amortize short-fixture bias
       F2d : longer-fixtures (C8-C10 prose ~700-1200 tokens)   ← DONE-Track-1

  L3 ⊘ chunk-ctx=64 ← small-fixture effective-sample-size low
     cause    : ctx=64 chunks-of-64 tokens from-128-token padded-seq
     impact   : 2-4 chunks per-fixture → bootstrap-CI wide
     severity : MEDIUM ← interpretation-confidence reduced
     fix-path :
       F3a : raise ctx to 256 or 512 ← model-VRAM permits
       F3b : token-level NLL ← maximum sample-granularity
       F3c : add larger fixtures (C8-C10 already ~500-1000 tokens) ← done

  L4 ⊘ subprocess-startup overhead per-file
     cause    : llama-perplexity.exe loads GGUF on-each-invocation
     impact   : 21-measurements run ~15-30min wallclock (load-time dominates)
     severity : MEDIUM ← throughput-affected • correctness unaffected
     fix-path :
       F4a : daemon-mode subprocess (stdin/stdout JSON-RPC)
       F4b : batch-mode (multiple files per-invocation)
       F4c : llama-cli --server with HTTP-API ← more infra
       F4d : direct-FFI long-term

  L5 ⊘ no audit-chain coupling with model-SHA
     cause    : model-weights SHA recorded-once-at-install not per-run
     impact   : if-model-file mutates post-install audit-chain misses-it
     severity : LOW ← models-on-disk rarely-mutate
     fix-path :
       F5a : compute model-SHA at each-run-entry ← add ~1s per-model
       F5b : binary-sha of llama-perplexity.exe ← currently TODO-marked

  L6 ⊘ Vulkan-backend GPU-dependent
     cause    : llama.cpp Vulkan-path requires Intel-Arc or-equiv GPU
     impact   : CPU-only hosts 10-100× slower
     severity : LOW-on-Apocky-box ← Intel-Arc-A770 present
              HIGH-for-CI-runners ← typical CPU-only
     fix-path :
       F6a : document CPU-fallback + extend timeouts in-CI
       F6b : smaller-models-on-CI (1.5B-Qwen only)
       F6c : cached-results in-repo + skip-run-on-CI

§§ PRIORITIZED FIX-ORDER

  priority-1 (immediate • non-invasive) :
    F4b : batch-mode subprocess ← reduces load-time 3×
    F5a : model-SHA per-run ← closes audit-gap
    F5b : binary-SHA of perplexity.exe ← pin TODO-marker
    F3a : raise ctx to 256 ← better granularity

  priority-2 (Session-14+ • infrastructure) :
    F4a : daemon-mode subprocess with JSON-RPC
    F1a : switch to llama-cli --log-probs for per-token NLL
    F2a : real-pad instead-of repeat-pad

  priority-3 (Session-15+ • reduce-deps) :
    F1b : C-FFI to llama.cpp via Odin + llama.h
         (eliminates Python + llama-perplexity.exe • keeps llama.cpp C-lib)

  priority-4 (long-term • eliminate Layer-5) :
    F1d : bespoke-inference engine ← research-horizon (see §§ BESPOKE-ROADMAP)

═════════════════════════════════════════════════════════════════════════
§ BESPOKE-REPLACEMENT ROADMAP                                          →
═════════════════════════════════════════════════════════════════════════

§§ PHASING-STRATEGY

  phase-A : QUICK-WINS (weeks of-effort ← low-hanging)
  phase-B : INFRASTRUCTURE-ELIMINATION (months ← mid-effort)
  phase-C : RUNTIME-ELIMINATION (quarters ← high-effort)
  phase-D : RESEARCH-HORIZON (open-ended ← PhD-scale)

§§ ─────────────────────────────────────────────────────────────────
§§ PHASE-A : QUICK-WINS                                               ✓
§§ ─────────────────────────────────────────────────────────────────

  A1 Ed25519 signing                  (replaces: D40 cryptography-Python)
     scope     : pure-Odin Ed25519 sign + verify
     reference : RFC 8032 + TweetNaCl (~ 300 LOC C reference)
     LOC-est   : ~500 LOC Odin (with SHA-512)
     effort    : 1-2 sessions
     blocks    : nothing ← additive
     testing   : RFC-8032 test-vectors
     benefit   : Python-Ed25519 dep removed • audit-chain Odin-native
     risk      : cryptographic-correctness ← test-vectors mitigate

  A2 BLAKE3 hash                      (replaces: D11 blake3-Rust)
     scope     : pure-Odin BLAKE3 stream + finalize
     reference : BLAKE3 spec + C reference (~1000 LOC)
     LOC-est   : ~800 LOC Odin
     effort    : 1 session
     testing   : BLAKE3 KAT test-vectors
     benefit   : LSP-layer one-less Rust-crate ; audit-chain portability

  A3 SHA-256 hash                     (utility • same principle as A2)
     scope     : FIPS-180-4 in-Odin
     LOC-est   : ~200 LOC
     effort    : 0.5 session
     benefit   : manifest.sha256 generation Odin-native

  A4 JSON parser + emitter            (replaces: D10 serde-Rust + D42 jsonschema)
     scope     : RFC-8259 compliant parser + deterministic emitter
     LOC-est   : parser ~600 + emitter ~400 = ~1000 LOC Odin
     effort    : 1-2 sessions
     benefit   : LSP+emit+audit all-use bespoke-JSON ← no external
     risk      : edge-cases (unicode-escape • number-precision) ← test-suite

  A5 JSON-Schema validator            (replaces: D42 jsonschema-Python)
     scope     : Draft-07 subset sufficient for-our-schemas
     LOC-est   : ~800 LOC Odin
     effort    : 1 session
     benefit   : self-validating emit-schemas • no Python-dep

  A6 Levenshtein distance             (replaces: D14 levenshtein-Rust)
     scope     : Wagner-Fischer O(mn)
     LOC-est   : ~50 LOC Odin
     effort    : 30 min
     benefit   : LSP code-action-suggest Odin-native

  A7 URI parser                       (replaces: D17 url + D18 percent-encoding)
     scope     : RFC-3986 URI parsing + percent-encoding
     LOC-est   : ~400 LOC Odin
     effort    : 1 session
     benefit   : LSP-layer dep-reduction • also needed-by LSP-client-messages

  A8 Regex engine (Thompson-NFA)      (replaces: D13 regex-Rust + D20 regex-syntax)
     scope     : Thompson-NFA • no-backtracking • O(mn) worst-case
     LOC-est   : ~2000 LOC Odin (parser + VM)
     effort    : 2-3 sessions
     benefit   : large-Rust-dep-tree cut • ~50 transitive-deps eliminated
     caveat    : PCRE-features not-supported (acceptable for-our use)

  A9 Daemon-mode subprocess           (shores-up L4 ← from §§ CLI-BACKEND)
     scope     : launch llama-perplexity.exe once + pipe JSON-RPC
     LOC-est   : ~200 LOC Python ← glue existing harness
     effort    : 0.5 session
     benefit   : 3× wallclock speedup on-21-measurements

  A10 Model-SHA + binary-SHA audit    (shores-up L5)
     scope     : hash model-file + llama-perplexity.exe at-each-run
     LOC-est   : ~50 LOC Python
     effort    : 0.5 session
     benefit   : audit-chain tamper-evident + release-reproducible

  phase-A total-estimate :
    LOC   : ~6000 LOC Odin + ~250 LOC Python-glue
    effort: 10-15 sessions
    deps-removed : 6 direct + ~50 transitive (Rust + Python)

§§ ─────────────────────────────────────────────────────────────────
§§ PHASE-B : INFRASTRUCTURE-ELIMINATION                               ○
§§ ─────────────────────────────────────────────────────────────────

  B1 LSP-server rewrite in-Odin       (replaces: D04-D28 Rust-toolchain + deps)
     scope     : full LSP v3.17 subset ← tower-lsp ← pure-Odin
     LOC-est   : ~5000 LOC Odin (matches Session-9 Rust 3524-LOC)
     effort    : 4-6 sessions
     benefit   : eliminates Rust + 50+ crates + Cargo + LLVM-for-Rust
              single-toolchain : Odin-only for-all-native-code
     blocks    : A4 JSON + A7 URI + A8 regex + A2 BLAKE3 (prereqs)
     risk      : async-model in-Odin ← cooperative-multitasking or-threads
              (Rust tokio has-zero direct-equivalent in-Odin)
     approach  : coroutine-pattern via-Odin-threads + message-queue
     test-pass : same integration-suite from-Session-9 (17 methods + VSCode)

  B2 Flat-file workspace-index        (replaces: D09 SQLite + rusqlite)
     scope     : append-only log + periodic-compact ← poor-man's-SQLite
     LOC-est   : ~400 LOC Odin
     effort    : 1 session
     benefit   : drop SQLite-C-dep • smaller-binary • no-C-build needed
     caveat    : slower-query for-big-workspaces ← acceptable for-LSP
     alt       : bespoke B-tree index (~1500 LOC ← higher effort)

  B3 VSCode-extension bundle-free     (replaces: D32 vscode-languageclient)
     scope     : thin TypeScript client ← direct LSP stdio-JSON
     LOC-est   : ~300 LOC TypeScript
     effort    : 1 session
     benefit   : drop npm-dep-tree ← only tsc + vscode-engine remain
     caveat    : VSCode-itself + TypeScript-itself still-external

  B4 HTML emitter validator           (replaces: D44 html5lib)
     scope     : subset-parser for-our-own-emitted HTML
     LOC-est   : ~500 LOC Odin
     effort    : 1 session
     benefit   : self-contained emit-validation ← no Python-dep

  B5 Markdown parser                   (replaces: D43 pandoc for-our-emit-check)
     scope     : CommonMark-subset for-our-own-emitted MD
     LOC-est   : ~1500 LOC Odin
     effort    : 2 sessions
     benefit   : MD-round-trip entirely-Odin
     caveat    : full CommonMark = hard ← restrict-to-subset we-emit

  B6 LaTeX compile-check              (replaces: D45 latexmk dependency)
     scope     : strict mode : rasterize + byte-compare vs-golden
     strategy  : accept-LaTeX-still-external-dep • improve-harness
     effort    : 0.5 session improvements
     benefit   : none-structural ← LaTeX fundamentally-external
     alt       : drop-LaTeX-target entirely (user-decision)

  B7 C-FFI to llama.cpp               (replaces: D37 Python + D38 exe)
     scope     : Odin-bindings for-llama.cpp C-API
     LOC-est   : ~1500 LOC Odin (bindings + Python-equivalence layer)
     effort    : 3-4 sessions
     benefit   : per-token NLL + daemon-semantics + batch-native
              eliminates Python entirely for-m₂ path
     caveat    : llama.cpp still-required ← not-yet-bespoke

  phase-B total-estimate :
    LOC   : ~10000 LOC Odin + ~300 LOC TypeScript
    effort: 12-18 sessions
    deps-removed :
      ✓ Rust toolchain + all-Rust-crates (50+)
      ✓ SQLite
      ✓ Python (for-m₂ path)
      ✓ npm-ecosystem (keep only vscode-engine + tsc)
    remaining-deps :
      Odin + MSVC-linker + VSCode + TypeScript-compiler + llama.cpp + Z3 + CVC5

§§ ─────────────────────────────────────────────────────────────────
§§ PHASE-C : RUNTIME-ELIMINATION                                      ○○
§§ ─────────────────────────────────────────────────────────────────

  C1 Bespoke SMT-solver                (replaces: D34 Z3 + D35 CVC5)
     scope     :
       theories : QF_LIA + QF_LRA + QF_UF + Array (subset)
       algorithm: DPLL(T) + Nelson-Oppen + Simplex + congruence-closure
       input    : SMT-LIB2 text (bespoke-parser from-A4 JSON pattern)
       output   : SAT + model-extraction OR UNSAT + proof-sketch
     LOC-est   : ~15000-25000 LOC Odin
       SMT-LIB2 parser       ~500
       DPLL SAT-core         ~3000
       Theory-combination    ~2000
       Simplex (LRA/LIA)     ~4000
       Congruence-closure    ~3000
       Array-theory          ~2000
       Model-extraction      ~2000
       Pre-processor         ~1500
       Test + harness        ~2000
     effort    : 40-60 sessions ← PhD-scale work
     benefit   : eliminates Z3 + CVC5 binaries
              single-binary for-CSLv3 + full-proof-chain
     blocks    : phase-B complete (infrastructure prereq)
     fallback  : keep-as-plug-in w/ Z3/CVC5 backends + bespoke-preferred
     reference : MiniSAT (~800 LOC) + CVC5-papers + CompCert-SMT-experiences

  C2 Bespoke LLM-inference              (replaces: D38 llama-perplexity + D41 sentence-transformers)
     scope     : ggml-equivalent quantized-inference ← CPU + Vulkan
     LOC-est   : ~25000-40000 LOC Odin
       Tensor-primitives       ~3000
       Quantization Q4_K_M     ~2000
       GGUF-loader             ~1500
       Matmul-kernels (CPU)    ~3000
       Matmul-kernels (Vulkan) ~5000 (SPIR-V emit from-CSSLv3)
       Attention-kernels       ~4000
       Tokenizer (BPE)         ~2000
       Inference-loop          ~3000
       Model-arch support      ~3000 (Llama + Qwen + Mistral families)
       Testing + bench         ~4000
     effort    : 60-100 sessions ← multi-month
     benefit   : eliminates llama.cpp + Python
              CSLv3-m₂ entirely-bespoke ← full reproducibility
              opens door to CSSLv3 integration (compute-shader emit)
     caveat    : massive-scope ← requires strong-motivation
     alternative : sampling-only (no-perplexity) ← need perplexity though
     reference : llama.cpp (~30000 LOC C++) + ggml + llm-c

  C3 Bespoke tokenizer for-m₂         (replaces: llama.cpp tokenizer)
     scope     : BPE-tokenizer matching HuggingFace format
     LOC-est   : ~1500 LOC Odin
     effort    : 2-3 sessions
     benefit   : per-model tokenizer-alignment (Session-12 reported miss)
              closes stratified-report agreement-verdict FLAG

  C4 Bespoke Odin-coroutine lib       (replaces: D06 tokio transitively)
     scope     : M:N coroutines + message-passing + select
     LOC-est   : ~3000 LOC Odin
     effort    : 5-8 sessions
     benefit   : LSP-server B1 async-primitive native
     prereq    : phase-B B1 attempts this subset

  phase-C total-estimate :
    LOC   : ~45000-70000 LOC Odin
    effort: 100-170 sessions ← years-at-current-cadence
    deps-removed :
      ✓ Z3 + CVC5
      ✓ llama.cpp + llama-perplexity
      ✓ GGUF-runtime external
      ◐ llama.cpp-tokenizer (C3 only)
    remaining-deps :
      Odin + MSVC-linker + VSCode + TypeScript-compiler

§§ ─────────────────────────────────────────────────────────────────
§§ PHASE-D : RESEARCH-HORIZON                                          ○○○
§§ ─────────────────────────────────────────────────────────────────

  D1 CSSLv3 self-hosts Odin-parser     (eliminates D01 Odin-toolchain)
     scope     : port parser to-CSSLv3 ← stage2+ of CSSLv3 plan
     LOC-est   : reuses Odin LOC ← translation-task
     effort    : CSSLv3-stage2 milestone ← per CSSLv3 roadmap
     benefit   : CSLv3 + CSSLv3 single-toolchain at-CSSLv3-stability
     caveat    : requires CSSLv3 reach stage2 self-hosted

  D2 Bespoke linker                    (eliminates D03 MSVC-linker)
     scope     : COFF + ELF + Mach-O output-emission
     LOC-est   : ~10000 LOC
     effort    : CSSLv3-stage3 scope per-existing CSSLv3 commitment
     benefit   : single-binary toolchain for-all-platforms

  D3 Bespoke VSCode-replacement        (eliminates D30 + D31 + D33)
     scope     : NOT recommended
     reason    : editor-ecosystem lock-in ← VSCode-replacement wastes effort
     alt       : ship Neovim-plugin + Emacs-mode + Zed + Helix clients
              ← multiple-editors covered without-building-one
     effort    : N/A (rejected)

  D4 Fully bespoke CI/release          (eliminates D46-D48 bash + git + coreutils)
     scope     : Odin-native release-driver
     LOC-est   : ~500 LOC
     effort    : 1-2 sessions
     benefit   : release.cmd single-Odin-binary ← no-shell-deps
     caveat    : git-itself remains ← users expect git-tags

  phase-D total :
    LOC    : ~10500 LOC
    effort : aligns-with CSSLv3 roadmap ← not-CSLv3-specific

═════════════════════════════════════════════════════════════════════════
§ AGGREGATE-ROADMAP                                                   ⊞
═════════════════════════════════════════════════════════════════════════

  phase   scope                               sessions  LOC-added    deps-removed
  ─────   ─────                               ────────  ─────────    ────────────
  A       quick-wins                          10-15     ~6000-Odin   6 direct
                                                                     50+ transitive
  B       infrastructure-elimination          12-18     ~10000-Odin  10 direct
                                                                     100+ transitive
  C       runtime-elimination                 100-170   ~50000-Odin  4 direct
                                                                     (all ML + SMT)
  D       research-horizon                    align-w/  ~10500-Odin  3 direct
                                                CSSLv3               (toolchain)
  ─────   ─────                               ────────  ─────────    ────────────
  TOTAL                                       130-200+  ~75000-Odin  23 direct
                                                                     150+ transitive

  remaining-after-D :
    Odin-compiler (self-hosting via CSSLv3-D1)
    VSCode-ecosystem (rejected for-effort-reasons)
    git (tolerable ← user-tool not-build-dep)
    LaTeX-distribution (optional ← target user-drops)

═════════════════════════════════════════════════════════════════════════
§ ROI-ORDERED RECOMMENDATIONS                                          D>
═════════════════════════════════════════════════════════════════════════

§§ IMMEDIATE (Session-13 + Session-14)
  ✓ A6 Levenshtein    ← trivial • 30 min
  ✓ A9 daemon-mode subprocess ← 3× m₂ speedup
  ✓ A10 model + binary SHA audit ← closes Session-12 TODO
  ✓ A3 SHA-256 hash ← manifest-generation Odin-native
  ✓ A1 Ed25519 ← audit-chain portable + enables Python-removal-later

§§ NEAR-TERM (Session-15 + Session-16)
  ⊙ A2 BLAKE3 ← feeds into-A4-JSON determinism
  ⊙ A4 JSON parser+emitter ← load-bearing for-A5 + B1 + B7
  ⊙ A5 JSON-Schema validator ← drops python-jsonschema
  ⊙ A7 URI parser ← LSP prereq

§§ MID-TERM (v1.2.x+ ← 3-6 months @ current-cadence)
  ⊙ A8 Regex engine ← huge Rust-dep-tree cut
  ⊙ B2 Flat-file workspace-index ← drops SQLite
  ⊙ B1 LSP-rewrite in-Odin ← drops Rust entirely
  ⊙ B7 C-FFI to llama.cpp ← drops Python-on-m₂
  ⊙ C4 Odin-coroutine lib ← B1 prereq

§§ LONG-TERM (v2.x horizon ← 12-24 months)
  ⊙ C1 Bespoke SMT-solver ← PhD-scale but-tractable
  ⊙ C3 Bespoke BPE tokenizer ← tokenizer-alignment
  ⊙ C2 Bespoke LLM-inference ← multi-month • research-grade

§§ RESEARCH-ALIGNED (aligns-w/ CSSLv3 roadmap)
  ⊙ D1 CSSLv3 self-hosts parser ← CSSLv3-stage2
  ⊙ D2 Bespoke linker ← CSSLv3-stage3
  ⊙ D4 Odin-native release-driver ← quick-win anytime

═════════════════════════════════════════════════════════════════════════
§ STABILITY GUARANTEE                                                   ‼
═════════════════════════════════════════════════════════════════════════

  all-replacements are DROP-IN ← zero user-visible-surface changes
    ✓ same CLI-flags
    ✓ same JSON-schemas
    ✓ same emit-formats
    ✓ same LSP-methods
    ✓ same audit-chain format
  ∴ replacement-work ≡ implementation-refactor ¬ semver-breaking
  ∴ can-ship in-PATCH-bumps (1.1.1 1.1.2 ...) or MINOR-bumps
  W! post-replacement validation :
    gold-suite per-replacement ← ∀ existing-tests pass
    output-byte-equivalence for-emit-targets
    checksum-parity for-audit-chain

═════════════════════════════════════════════════════════════════════════
§ DECISION-POINTS FOR APOCKY                                           Q?
═════════════════════════════════════════════════════════════════════════

  Q1 priority : phase-A complete-all OR cherry-pick ?
     recommend : A1+A3+A6+A9+A10 first ← closes Session-12 TODOs + audit gaps
     alt       : A2+A4 first ← unblocks biggest future-wins (B1 LSP-rewrite)

  Q2 ambition : pursue phase-C (SMT+LLM bespoke) ?
     recommend : defer-decision until phase-B complete
     ∵ phase-B exposes clearer V ≡ experience-with-Odin-infrastructure
     Apocky-call : research-horizon-project OR pragmatic-stopping-point

  Q3 LSP-rewrite : Session-14 OR Session-20 ?
     recommend : after-A2+A4+A7 prereqs • approximately Session-18+
     ∵ scope ~5000 LOC + async-challenge ← need solid-quick-wins first

  Q4 CSSLv3-parallel : accelerate-CSSLv3 OR deepen-CSLv3 ?
     note      : CSSLv3-stage1 self-host makes D1+D2 automatic
     Apocky-call : strategic-branching-decision

  Q5 user-facing : is v1.1.x visible ⊆ current-user-set ?
     ∵ replacements matter if-users-care
     ∵ if-Apocky-sole-user dep-elimination is internal-quality not-user-value
     Apocky-call : project-scope-definition

═════════════════════════════════════════════════════════════════════════
§ CROSS-REFERENCE                                                      ⊞
═════════════════════════════════════════════════════════════════════════

  CSSLv3 no-LLVM commitment ← this-roadmap aligns
  CSSLv3 proprietary-for-everything @ stage1+ ← D-phase reciprocal
  PRIME_DIRECTIVE.md Lazarus-ownership ← self-hosted-toolchain reinforces
  CSLv3 v1.0 STABILITY ← all-phases additive-only ← guarantee holds

═════════════════════════════════════════════════════════════════════════
§ NEXT-ACTIONS                                                         →
═════════════════════════════════════════════════════════════════════════

  ◐ Apocky : select phase-A priority-set (Q1)
  ◐ Apocky : decide Q2 ambition-level
  ◐ agent : Session-14 handoff per-selection
  ◐ agent : when green-lit, execute phase-A task-by-task
  ◐ agent : update STABILITY.md + CHANGELOG.md per-replacement

∎ DEPENDENCY-RESEARCH-V1
