<!-- schema: markdown-v1 -->
<!-- source: parser/tests/C7\_morpheme\_stack.csl -->

# C7\_morpheme\_stack


## morpheme.stacking
<a id="morphemestacking"></a>


## ASPECT-ONLY
<a id="aspect-only"></a>

```csl
# tests: morpheme stacking BASE.aspect.modality.certainty.scope (§03)
# glyph-class: Dot compound, dotted suffix chains
# features: .prog .perf .iter .inch .term, .must .may .cant, .cert .prob, .loc .glob
render.prog : bool
```

```csl
merge.perf : bool
```

```csl
spawn.iter : bool
```

```csl
compact.inch : bool
```

```csl
sync.term : bool
```


## MODALITY-ONLY
<a id="modality-only"></a>

```csl
commit.must : bool
```

```csl
retry.may : bool
```

```csl
reorder.cant : bool
```


## CERTAINTY-ONLY
<a id="certainty-only"></a>

```csl
pass.cert : bool
```

```csl
drift.prob : bool
```

```csl
stall.poss : bool
```


## SCOPE-ONLY
<a id="scope-only"></a>

```csl
cache.loc : bool
```

```csl
cache.glob : bool
```


## TWO-STACK
<a id="two-stack"></a>

```csl
render.prog.cert : bool
```

```csl
merge.inch.must : bool
```

```csl
spawn.iter.may : bool
```


## THREE-STACK
<a id="three-stack"></a>

```csl
allocate.prog.prob.loc : bool
```

```csl
cleanup.perf.must.glob : bool
```


## FOUR-STACK
<a id="four-stack"></a>

```csl
reconcile.iter.may.doubt.ctx : bool
```


## FIVE-STACK
<a id="five-stack"></a>

```csl
transmit.prog.may.poss.loc : bool
```

