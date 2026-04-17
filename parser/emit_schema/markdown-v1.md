# CSLv3 Markdown Emit — Style Guide (`markdown-v1`)

**Format:** GitHub-Flavored Markdown (GFM)

## Structural contract

- First line: `<!-- schema: markdown-v1 -->` (parseable version marker)
- Second line: `<!-- source: <path> -->` (provenance)
- Third block: `# <derived-title>` (derived from filename stem)
- Each `§ Name` section → a level-2 heading `## Name` preceded by a blank line
- Each section body rendered as fenced `csl` code-block reconstructed via pprint

## Cross-reference scheme

Auto-generated anchor syntax: `<a id="<anchor>"></a>` immediately after each
heading, where `<anchor>` = slug(lowercase, dashes-for-spaces, a-z0-9-only).
Cross-refs from other renderers use `[label](#anchor)`.

## Accessibility notes

Ruby annotations wrap glyph-heavy sequences for screen-reader text-to-speech
when the `--emit=markdown --ruby` flag is set (future feature). The base
`markdown-v1` emit preserves glyphs raw inside fenced blocks.

## Comment handling

CSL `#` comments render as Markdown blockquotes (`> <text>`) to preserve
their narrative role without conflating with code.

## Consumers

- Static-site generators (Jekyll, Hugo, Next.js MDX)
- GitHub / GitLab / Gitea repo browsers
- `pandoc` conversion to HTML, PDF, DOCX, ePub
- Documentation hosts (Docusaurus, Astro, mdBook with adapters)
