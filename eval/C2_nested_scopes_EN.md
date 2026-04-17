# C2 — Nested Scope Structure (English)

This test exercises the parser's handling of deeply nested sections and
the mechanics of indentation-as-scope-boundary, inspired by Peirce's
existential graphs where enclosure represents logical scope.

There is an outer section at the top level. Inside it are two sub-sections
introduced by double-section markers. The first sub-section contains two
simple definitions: a name of string type, and an active flag of boolean
type. The second sub-section contains two deeply nested levels introduced
by triple-section markers.

The first deeply nested sub-section contains two definitions: a nested
value of 32-bit signed integer type and an inner field of 8-bit unsigned
integer type. The second deeply nested sub-section contains a single
field of 32-bit floating point type.

After the deeply nested sections, we return to double-section level with
a sibling sub-section containing a reset flag of boolean type. Finally,
the document closes with a new top-level section containing a single
flat field, and an empty trailing section.

The parser's indentation stack must handle the transitions between
these depths correctly, emitting the right sequence of indent and dedent
tokens so that the AST has the correct hierarchical structure rather
than a flattened one.
