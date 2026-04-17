# CSLv3 Language Support

Syntax highlighting, diagnostics, hover, completion, and more for
[Caveman Spec Language v3](../../../) — an ultra-dense specification
notation built for human + AI + compiler consumption.

## Features

- **Syntax highlighting** — 74-glyph master-set, morphemes (`'d 'f 's 't 'e 'm 'p 'g 'r`),
  section markers (`§ ¶`), modals (`I> W! R! M? N! Q?`), evidence markers
  (`✓ ◐ ○ ✗ ⊘ △ ▽ ‼`), compound operators (`. + - ⊗ @`).
- **Diagnostics** — real-time parse + type-check + permissive-accept warnings
  via the `cslv3-lsp` language server + `parser.exe` backend. SMT obligations
  + opt-pass statistics surface via configuration.
- **Hover** — Unicode glyph lookup (ASCII alias + category + docs-ref),
  morpheme-expansion with refinement formula, inferred type via type-checker.
- **Completion** — context-aware after trigger characters:
  - `'` → 9 morpheme tags
  - `§` → section modals
  - `.` / `⊗` / `@` / `+` → Sanskrit compound operators
  - `:` → type completions (primitives + user-defined)
- **Formatting** — whole-document via `parser.exe --mode=canonical`.
- **Go-to-definition + references** — via IR use-def chains, with
  workspace-index for cross-file lookup.
- **Document + workspace symbols** — outline tree + fuzzy search.
- **Code actions** — quick-fix suggestions for unknown morphemes
  (Levenshtein-nearest), permissive-accept promote, type-mismatch hints.
- **Semantic tokens** — 74-glyph highlighting that extends beyond
  the TextMate grammar.

## Setup

1. Build the language server:
   ```sh
   cd lsp
   cargo build --release
   ```
2. Build the `parser.exe` Odin toolchain:
   ```sh
   odin build parser/ -out:parser.exe
   ```
3. Install the VSCode extension (this folder) via `Extensions: Install from
   VSIX…` after `vsce package`, or by copying to
   `~/.vscode/extensions/cslv3-<version>/`.

## Configuration

| Setting                  | Default   | Description |
|--------------------------|-----------|-------------|
| `cslv3.server.path`      | auto      | Absolute path to `cslv3-lsp.exe` |
| `cslv3.parser.path`      | auto      | Absolute path to `parser.exe` |
| `cslv3.server.logLevel`  | `warn`    | `trace` / `debug` / `info` / `warn` / `error` |
| `cslv3.smtOnSave`        | `false`   | Run SMT discharge on file save (slower) |
| `cslv3.optLevel`         | `-1`      | IR-opt level (`-1` disables; `0..3` enables) |
| `cslv3.showOptStats`     | `false`   | Surface pass-statistics as Information diagnostics |
| `cslv3.severity`         | `default` | `lint` / `default` / `strict` |

## Commands

- `CSLv3: Discharge SMT obligations` — on-demand SMT discharge
- `CSLv3: Show opt-pass statistics` — per-pass applied/skipped counts
- `CSLv3: Restart language server`

## License

MIT
