# Design Retrospective — Parser Bootstrap

## Overview

Building a reference parser for a notation language is different from building a parser for a mainstream programming language. The grammar itself is in flux during early development, the target audience starts at zero (there are no existing files to test against), and the notion of a "correct parse" is entangled with the notation's semantic goals. This note captures the reasoning behind three specific early decisions made during the CSLv3 parser bootstrap in the opening sessions.

## Decision One : Odin over Rust

The parser is written in Odin, not Rust. This is unusual enough to deserve explanation. Rust would have given us a larger ecosystem, a more familiar set of libraries, and easier cross-compilation. Odin was chosen for three pragmatic reasons. First, Odin compile times are dramatically lower than Rust compile times at this scale, which matters when the parser is rebuilt dozens of times per session during notation evolution. Second, Odin's error handling is simpler and produces smaller binaries, and the LSP server layer was always planned to be Rust anyway, giving us natural language separation between substrate (Odin) and tooling (Rust). Third, the spec author had existing Odin familiarity and zero Rust-async familiarity at the time of bootstrap, which made the ramp shorter.

This decision is likely to survive the full v1.x series. Migrating the parser to Rust would be a one-month effort with no user-visible gain.

## Decision Two : Comments Dropped by Default

The lexer drops hash-to-end-of-line comments by default. This was a load-bearing choice for round-trip semantics: round-trip equality is defined on AST shape, not source text. Preserving comments would have required either attaching them to AST nodes (complicating the shape) or maintaining a parallel token stream through every transformation pass (doubling implementation cost for every pretty-printer mode).

The tradeoff was eventually revisited in Session 5 (T23), which introduced optional comment preservation, but the default remained off for performance and RT-predictability reasons. Users who need comment preservation must opt in explicitly.

## Decision Three : Strict Grammar with Permissive Parse

The parser accepts some malformed input without emitting a parse error, deferring the complaint to the semantic layer. Thirteen specific patterns were identified during Session 4 that the parser accepts silently and that the semantic pass then flags. This two-tier approach keeps editor latency low (mid-typing code is frequently malformed and should not trigger cascading parse errors) while still producing the correct diagnostic on save.

The strict-parse command-line flag escalates these permissive cases back to parse errors for build-gate and CI-lint use cases.

## Reflection

None of these three decisions was obvious at the time. Each required several alternative paths to be explored and rejected before settling on the chosen design. The decisions-log file in the parser directory records every such rejection with dated rationale so that future contributors do not revisit the same design territory without reading the prior art.

## Takeaway

Parser bootstrap decisions cost little at day one and a great deal at month six. Write them down as you make them, and make the write-up part of the pull-request review, not an afterthought.
