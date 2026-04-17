# C5 — Bridge Mode (English + CSL interleaved)

This document demonstrates bridge mode, where English prose sits next
to structured CSLv3. Readers unfamiliar with the notation can still
follow the intent while the parser extracts only the structured regions
for static analysis.

## Goal

We want to describe an HTTP request handler pipeline. The prose here
describes the what and why; the structured blocks below give the
machine-readable signatures.

## Structured data

The request type has a method field (the HTTP verb), a path field (the
URL path portion), and a body field (the raw payload bytes). The
response type has a status field (numeric HTTP status), a body field
(the response payload bytes). Both types are defined below in CSLv3
records.

## Inline explanation

The function's contract is that any valid request maps to exactly one
response — there is no path where the handler returns zero responses
or more than one.

## Operations

The handler takes a reference to a request and returns a response.
This is the single entry point; all routing, processing, and output
generation happens inside it.

## Invariants

Determinism: the same request should yield the same response. Request
to response is a total, single-valued mapping.
