# C2 — Nested Scope Structure (English)

This test exercises the parser's handling of deeply nested sections and
the mechanics of indentation-as-scope-boundary, inspired by Peirce's
existential graphs where enclosure represents logical scope. The fixture
was expanded in Session-13 so that natural token count exceeds twice the
perplexity context size, eliminating the need for repeat-padding in the
m2 harness and the associated KV-cache over-collapse artefact that
dominated the prior baseline.

## Structure

The document organizes five top-level sections.

The outer section contains four sub-sections at depth two. The first
sub-section called first-sub declares four definitions: a name of string
type, an active flag of boolean type, an id of unsigned 64-bit integer
type, and a created timestamp. The second sub-section called second-sub
contains three deeply-nested sub-sections at depth three.

The first deeply-nested block called deep-sub declares four definitions:
a nested value of 32-bit signed integer type, an inner field of 8-bit
unsigned integer type, a flags field of 16-bit unsigned integer type
carrying a bahuvrihi compound expressing possession of read, write, and
execute permissions, and a parent identifier of 32-bit unsigned integer
type.

The second deeply-nested block called another-deep contains three
32-bit or 64-bit floating point definitions: an item, a ratio, and a
scaling factor. The third deeply-nested block called triple-peer holds
a symbolic tag, a signed 64-bit value, and an owner identifier as a
32-bit unsigned integer.

Returning to depth two, a sibling sub-section called sibling-after-deep
provides a reset flag, a cleared-at timestamp, and a reason string. A
config-sub sibling holds two tunable-depth definitions of maximum
nesting and stride as 8-bit unsigned integers with defaults, and two
default-depth definitions for minimum nesting and an optional flag.

A second top-level section called next-top contains a flat 32-bit
integer and a string label, with two sub-sections: attached, which
tracks hit-points and their maximum, and detached, which tracks a
visibility flag.

A third top-level section called middle-top has an owner-path
sub-section with a path-length counter, leaf identifier, and grandchild
identifier as 32-bit unsigned integers, plus a deeper owner-deep
sub-section containing a 64-bit handle and a symbolic state.

A fourth top-level section called math-top collects three vector-field
sub-sections: position, velocity, and acceleration as three-component
vector properties using the property-type suffix. A scalars sub-section
holds mass, charge, and temperature as 32-bit floats. A units
sub-section beneath it binds distance in meters, time in seconds, and
angle in radians via the avyayibhava scope operator.

A fifth top-level section called rule-top lists invariants as MUST
constraints: the active flag implies a positive id, every sub-section
must have a non-null owner, and circular parent chains are forbidden.
A flow sub-section describes state transitions: create sets active
true, destroy sets active false, and reset restores hit-points to
maximum.

## Termination

The document closes with an empty trailing section labelled final that
provides a no-content terminator for the parser to handle gracefully.

## Parser requirements

The indentation stack must handle transitions between these five depth
levels correctly. It must emit the right sequence of indent and dedent
tokens so the abstract syntax tree reflects the correct hierarchical
structure rather than a flattened one. The expanded corpus exercises
deep chains through identifier fields, symbolic state types,
unit-of-measure annotations, and constraint sections, providing a more
comprehensive cross-section of real-world CSL usage than the minimal
original fixture. It is the canonical test for the parser's INDENT,
DEDENT, and NEWLINE emission under complex nested section hierarchies.

## Properties verified

- Multi-depth section markers produce correct tree shape.
- Sibling sections at the same depth do not merge.
- Returning from depth three to depth two emits DEDENT tokens.
- Definitions inside a section attach to that section, not parent.
- Empty sections parse without hanging.
- Default values on integer fields produce the correct type.
- Pointer-style fields use unsigned identifier syntax.
- Bahuvrihi compounds declare permission flags.
- Property-type suffixes apply to vector fields.
- Unit annotations attach via the scope operator.
- MUST and MUST NOT rules parse as invariants.
- Flow transitions parse as directed edges.

The expansion is intentionally lexically dense with repeated field
syntax so the natural token count surpasses twice the context size,
avoiding the artificial KV-cache amplification that makes regular
short fixtures report anomalously low m2 under repeat-pad.
