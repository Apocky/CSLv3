<!-- schema: markdown-v1 -->
<!-- source: parser/tests/C5\_bridge\_mode.csl -->

# C5\_bridge\_mode


## bridge.example
<a id="bridgeexample"></a>


## GOAL
<a id="goal"></a>

```csl
# tests: mixed EN prose + CSL fragments (§09 bridge mode)
# glyph-class: Comment preservation, ident-heavy lines, embedded structured blocks
# features: prose coexisting with parseable CSLv3 in the same document
# This document demonstrates bridge mode where English prose sits next to
# structured CSLv3. Readers unfamiliar with the notation can still follow
# the intent while the parser extracts only the structured regions.
# A short English paragraph would live here in practice. The compiler
# treats comment lines as prose and ignores them.
summary : str
```


## STRUCTURED
<a id="structured"></a>

```csl
def Request't ⟨
  method : str
  path : str
  body : str
⟩
```

```csl
def Response't ⟨
  status : u16
  body : str
⟩
```


## OPS
<a id="ops"></a>

```csl
# Inline explanation: the next function's contract is that any valid
# Request must map to exactly one Response. English above; CSL below.
fn handle (req : &Request't) -> Response't = Response't
```


## INVARIANTS
<a id="invariants"></a>

```csl
⌈determinism⌉
```

```csl
⌈request-maps-to-one-response⌉
```

