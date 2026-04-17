<!-- schema: markdown-v1 -->
<!-- source: parser/tests/C6\_slot\_grammar.csl -->

# C6\_slot\_grammar


## slot.grammar.coverage
<a id="slotgrammarcoverage"></a>


## MINIMAL
<a id="minimal"></a>

```csl
# tests: full slot template [EV] [MOD] [DET] [SUBJ] [REL] [OBJ] [GATE] [SCOPE]
# glyph-class: evidence markers, modal tokens, determinatives, relation operators
# features: every slot position exercised; silent defaults omitted where natural
x : i32
```

```csl
y : u8
```


## EVIDENCE-ONLY
<a id="evidence-only"></a>

```csl
[x] a : i32
```

```csl
[~] b : i32
```

```csl
[ ] c : i32
```

```csl
[!] d : i32
```


## MODAL-ONLY
<a id="modal-only"></a>

```csl
W! must-be-true : bool
```

```csl
R! should-hold : bool
```

```csl
M? may-happen : bool
```

```csl
N! must-not-fire : bool
```


## EVIDENCE-AND-MODAL
<a id="evidence-and-modal"></a>

```csl
[x] W! required-and-proven : bool
```

```csl
[~] R! suggested-partial : bool
```

```csl
[!] N! forbidden-and-failed : bool
```


## DET-WITH-SUBJECT
<a id="det-with-subject"></a>

```csl
∫density : f32
```

```csl
⊞chunk : u32
```


## RELATION-VARIANTS
<a id="relation-variants"></a>

```csl
a : i32
```

```csl
b :: entity
```

```csl
c = 10
```

```csl
x -> y
```

```csl
s <- src
```


## GATE-TRAILING
<a id="gate-trailing"></a>

```csl
active : bool if ready
```

```csl
pending : bool when unblocked
```


## SCOPE-TRAILING
<a id="scope-trailing"></a>

```csl
render : bool @frame
```

```csl
tick : bool @chunk
```


## FULL-SLOT
<a id="full-slot"></a>

```csl
[~] W! ∫flux :: stream @frame
```

```csl
[x] R! ⊞voxel : u32 @chunk
```

