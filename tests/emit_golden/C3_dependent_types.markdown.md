<!-- schema: markdown-v1 -->
<!-- source: parser/tests/C3\_dependent\_types.csl -->

# C3\_dependent\_types


## dependent.types
<a id="dependenttypes"></a>


## DATA
<a id="data"></a>

```csl
# tests: Π / Σ dependent types + refinement { x ⊢ P } + linear T!lin
# glyph-class: LAngle/RAngle, LBrace/RBrace, Entails, Bang, Ampersand
# features: type-level parameterization, pi/sigma records, refinements
def PosFloat't = f32
```

```csl
def UnitVec't = vec3
```

```csl
def BoundHp't = u16
```


## OPS
<a id="ops"></a>

```csl
fn make-vector (n : u32) -> vec3 = vec3
```

```csl
fn pair-len-and-data (n : u32) -> vec3 = vec3
```

```csl
fn normalize (v : &vec3) -> bool = true
```

```csl
fn borrow-shared (r : &str) -> bool = true
```

```csl
fn borrow-mut (r : &str) -> bool = true
```


## INVARIANTS
<a id="invariants"></a>

```csl
⌈refinement-sound⌉
```

```csl
⌈linear-used-exactly-once⌉
```

