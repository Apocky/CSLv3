# C6 — Slot Grammar Coverage (English)

This test exhaustively exercises the CSLv3 slot template. Every
statement has a fixed positional structure with the following ordered
slots, each of which is optional and defaults to silent when omitted:
evidence marker, modal operator, determinative prefix, subject term,
relation operator, object term, gate clause, scope clause, and meta
comment.

## Minimal statements

The simplest definitions have only a subject and an object joined by
the default relation. For example, declaring x to be a 32-bit signed
integer, or y to be an 8-bit unsigned integer.

## Evidence only

We can prefix a statement with an evidence marker to indicate the
status of the claim. The four markers in this section indicate that
entry a is confirmed, entry b is partial, entry c is pending, and
entry d is failed.

## Modal only

We can instead prefix with a modal operator to express obligation
strength. We show statements marked as must-be-true, should-hold,
may-happen, and must-not-fire.

## Evidence and modal combined

These can stack. Here we show confirmed-and-required, partial-and-
recommended, and failed-and-forbidden combinations.

## Determinative with subject

Some subjects carry a domain-determinative prefix to indicate category.
The field determinative marks continuous quantities like density; the
spatial determinative marks discrete grid-like quantities like chunk
identifiers.

## Relation variants

Beyond the default binding relation, statements can use type-of,
equals, flow-arrow, or source-from as the explicit relation operator.

## Trailing gate

Any statement may carry a trailing gate clause introduced by if, when,
unless, or while, attaching a conditional predicate to the statement.

## Trailing scope

Any statement may also carry a trailing scope clause introduced by
@, per, or in, attaching a scope or frequency qualifier.

## Full slot

Finally, we show statements with every slot populated: evidence plus
modal plus determinative plus subject plus relation plus object plus
scope. These are uncommon in practice but exercise the full grammar.
