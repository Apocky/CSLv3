<!-- schema: markdown-v1 -->
<!-- source: parser/tests/C2\_nested\_scopes.csl -->

# C2\_nested\_scopes


## outer
<a id="outer"></a>


## first-sub
<a id="first-sub"></a>

```csl
# tests: deep indent + §§ subsection nesting + indent-as-cut (Peirce)
# glyph-class: Section, Indent, Dedent
# features: multiple `§` depth, nested indent blocks, sibling sections
name : str
```

```csl
active : bool
```


## second-sub
<a id="second-sub"></a>


## deep-sub
<a id="deep-sub"></a>

```csl
nested : i32
```

```csl
inner : u8
```


## another-deep
<a id="another-deep"></a>

```csl
item : f32
```


## sibling-after-deep
<a id="sibling-after-deep"></a>

```csl
reset : bool
```


## next-top
<a id="next-top"></a>

```csl
flat : i32
```


## final
<a id="final"></a>

