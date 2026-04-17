<!-- schema: markdown-v1 -->
<!-- source: parser/tests/C1\_sort.csl -->

# C1\_sort


## sort.spec
<a id="sortspec"></a>


## GOAL
<a id="goal"></a>


## DATA
<a id="data"></a>

```csl
# what: in-place comparison sort
# why:  predictable worst-case, zero allocations
def Arr't = [i32; _]
```

```csl
def Cmp't = i32 -> i32 -> bool
```


## OPS
<a id="ops"></a>

```csl
fn sort (a : &Arr't, cmp : Cmp't) -> bool = true
```

```csl
fn merge-sort (a : &Arr't, lo : i32, hi : i32, cmp : Cmp't) -> bool = true
```

```csl
fn merge (a : &Arr't, lo : i32, mid : i32, hi : i32, cmp : Cmp't) -> bool = true
```


## INVARIANTS
<a id="invariants"></a>

```csl
⌈time <= n⌉
```

```csl
⌈extra-space = n⌉
```


## TESTS
<a id="tests"></a>

```csl
[x] case1 : sort-empty-returns-true
```

```csl
[x] case2 : sort-one-returns-true
```

```csl
[x] edge : sort-reversed-returns-true
```


## ANTI-PATTERNS
<a id="anti-patterns"></a>

```csl
[!] recursion-on-tiny-subarrays
```

```csl
[x] insertion-sort-at-small-n
```

