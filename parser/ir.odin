package cslparser

// § CSLv3 IR — SSA + STRUCTURED REGIONS (T21 Session-6)
// I> MLIR-pattern : Op owns Region[] ; Region owns Block[] ; Block owns Op[]
// I> SSA via block-args (Cranelift/MLIR-style) — no classical phi nodes
// I> Values carry ^Type from T20 (parser/types.odin) for type-checked ops
// I> Braun-style on-the-fly SSA construction (no dominance-tree needed
//    ∵ structured-CFG has explicit region boundaries)
// I> Source positions preserved per-op for round-trip + error-reporting
// R! ← MLIR-pattern (SPIR-V-compatible for future CSSLv3-interop)
// R! ← Cranelift CLIF block-args (cleaner than phi)

import "core:fmt"
import "core:strings"

// ---------- ID generation ----------

@(private="file") g_next_value_id : int = 0
@(private="file") g_next_block_id : int = 0
@(private="file") g_next_op_id    : int = 0

ir_reset_ids :: proc() {
    g_next_value_id = 0
    g_next_block_id = 0
    g_next_op_id    = 0
}

@(private="file") fresh_value_id :: proc() -> int { g_next_value_id += 1 ; return g_next_value_id }
@(private="file") fresh_block_id :: proc() -> int { g_next_block_id += 1 ; return g_next_block_id }
@(private="file") fresh_op_id    :: proc() -> int { g_next_op_id    += 1 ; return g_next_op_id    }

// ---------- Attr ----------

Attr_Kind :: enum {
    Int, Float, Str, Bool, Symbol, Sig, Type, Label,
}

Attr :: struct {
    kind: Attr_Kind,
    int_v:   i64,
    float_v: f64,
    str_v:   string,
    bool_v:  bool,
    ty_v:    ^Type,    // for Type-attrs (carries Type_Ref)
}

attr_int    :: proc(v: i64)      -> Attr { return Attr{kind=.Int,    int_v=v} }
attr_float  :: proc(v: f64)      -> Attr { return Attr{kind=.Float,  float_v=v} }
attr_str    :: proc(v: string)   -> Attr { return Attr{kind=.Str,    str_v=v} }
attr_bool   :: proc(v: bool)     -> Attr { return Attr{kind=.Bool,   bool_v=v} }
attr_symbol :: proc(v: string)   -> Attr { return Attr{kind=.Symbol, str_v=v} }
attr_type   :: proc(t: ^Type)    -> Attr { return Attr{kind=.Type,   ty_v=t} }
attr_label  :: proc(s: string)   -> Attr { return Attr{kind=.Label,  str_v=s} }

// ---------- Value ----------
// A Value is either :
//   (a) the Nth result of an Op, OR
//   (b) a Block_Arg (parameter of a Block — SSA incoming edge value).

Value_Def_Kind :: enum { From_Op, From_Block_Arg }

Value :: struct {
    id:       int,          // %N in textual form
    name:     string,        // optional friendly name (debug / hover)
    ty:       ^Type,         // type from T20
    def_kind: Value_Def_Kind,
    def_op:    ^Op,          // if From_Op
    def_block: ^Block,       // if From_Block_Arg (block this value belongs to)
    def_arg_idx: int,        // if From_Block_Arg : index within block.args
}

new_value :: proc(ty: ^Type, name: string = "") -> ^Value {
    v := new(Value)
    v.id = fresh_value_id()
    v.ty = ty
    v.name = name
    return v
}

value_from_op :: proc(op: ^Op, idx: int = 0, ty: ^Type = nil, name: string = "") -> ^Value {
    v := new_value(ty, name)
    v.def_kind = .From_Op
    v.def_op = op
    return v
}

value_from_block_arg :: proc(block: ^Block, idx: int, ty: ^Type, name: string = "") -> ^Value {
    v := new_value(ty, name)
    v.def_kind = .From_Block_Arg
    v.def_block = block
    v.def_arg_idx = idx
    return v
}

// ---------- Block ----------

Block :: struct {
    id:     int,
    label:  string,          // "entry" | "then" | "else" | etc.
    args:   [dynamic]^Value,   // SSA-incoming values
    ops:    [dynamic]^Op,       // body ops ; last is the terminator
    parent: ^Region,
}

new_block :: proc(label: string, parent: ^Region = nil) -> ^Block {
    b := new(Block)
    b.id = fresh_block_id()
    b.label = label
    b.args = make([dynamic]^Value)
    b.ops = make([dynamic]^Op)
    b.parent = parent
    return b
}

block_add_arg :: proc(b: ^Block, ty: ^Type, name: string = "") -> ^Value {
    v := value_from_block_arg(b, len(b.args), ty, name)
    append(&b.args, v)
    return v
}

block_terminator :: proc(b: ^Block) -> ^Op {
    if b == nil || len(b.ops) == 0 do return nil
    last := b.ops[len(b.ops) - 1]
    if op_is_terminator(last) do return last
    return nil
}

// ---------- Region ----------

Region :: struct {
    id:        int,           // tied to block-id-counter for uniqueness
    blocks:    [dynamic]^Block,
    parent_op: ^Op,
    // structural kind — enforced by verifier (fn-body vs then-branch vs while-cond etc.)
    kind:      Region_Kind,
}

Region_Kind :: enum {
    Generic,      // default
    Fn_Body,
    If_Then,
    If_Else,
    While_Cond,
    While_Body,
    For_Body,
    Match_Arm,
    Match_Default,
    Handler_Body,
}

new_region :: proc(parent: ^Op, kind: Region_Kind = .Generic) -> ^Region {
    r := new(Region)
    r.blocks = make([dynamic]^Block)
    r.parent_op = parent
    r.kind = kind
    return r
}

region_add_block :: proc(r: ^Region, b: ^Block) {
    b.parent = r
    append(&r.blocks, b)
}

region_entry_block :: proc(r: ^Region) -> ^Block {
    if r == nil || len(r.blocks) == 0 do return nil
    return r.blocks[0]
}

// ---------- Op ----------

Op :: struct {
    id:       int,
    name:     string,          // e.g., "cslv3.const"
    operands: [dynamic]^Value,
    results:  [dynamic]^Value,  // every result is a Value.From_Op pointing back here
    regions:  [dynamic]^Region,
    attrs:    map[string]Attr,
    loc:      Source_Pos,
    parent:   ^Block,           // containing block (nil if module-root)
}

new_op :: proc(name: string, loc: Source_Pos = {}) -> ^Op {
    op := new(Op)
    op.id = fresh_op_id()
    op.name = strings.clone(name)
    op.operands = make([dynamic]^Value)
    op.results = make([dynamic]^Value)
    op.regions = make([dynamic]^Region)
    op.attrs = make(map[string]Attr)
    op.loc = loc
    return op
}

op_add_operand :: proc(op: ^Op, v: ^Value) {
    if v != nil do append(&op.operands, v)
}

op_add_result :: proc(op: ^Op, ty: ^Type, name: string = "") -> ^Value {
    v := value_from_op(op, len(op.results), ty, name)
    append(&op.results, v)
    return v
}

op_add_region :: proc(op: ^Op, r: ^Region) {
    r.parent_op = op
    append(&op.regions, r)
}

op_set_attr :: proc(op: ^Op, key: string, a: Attr) {
    op.attrs[strings.clone(key)] = a
}

op_get_attr :: proc(op: ^Op, key: string) -> (a: Attr, ok: bool) {
    a, ok = op.attrs[key]
    return
}

op_is_terminator :: proc(op: ^Op) -> bool {
    if op == nil do return false
    switch op.name {
    case "cslv3.return", "cslv3.break", "cslv3.continue",
         "cslv3.branch", "cslv3.cond_branch", "cslv3.yield":
        return true
    }
    return false
}

block_append_op :: proc(b: ^Block, op: ^Op) {
    op.parent = b
    append(&b.ops, op)
}

// ---------- Module ----------

Module :: struct {
    ops:   [dynamic]^Op,       // top-level ops : fn, type-def, etc.
    attrs: map[string]Attr,
    source_file: string,
}

new_module :: proc(source_file: string = "") -> ^Module {
    m := new(Module)
    m.ops = make([dynamic]^Op)
    m.attrs = make(map[string]Attr)
    m.source_file = source_file
    return m
}

module_append_op :: proc(m: ^Module, op: ^Op) {
    append(&m.ops, op)
}

// ---------- Op-name constants (canonical strings) ----------
// Kept in one place so lower.odin + ir_verify.odin + ir_print.odin agree.

OP_MODULE  :: "cslv3.module"
OP_FN      :: "cslv3.fn"
OP_RETURN  :: "cslv3.return"
OP_CONST   :: "cslv3.const"
OP_VAR_REF :: "cslv3.var_ref"
OP_RECORD  :: "cslv3.record"
OP_PROJ    :: "cslv3.proj"
OP_VARIANT :: "cslv3.variant"
OP_MATCH   :: "cslv3.match"
OP_ADD     :: "cslv3.add"
OP_SUB     :: "cslv3.sub"
OP_MUL     :: "cslv3.mul"
OP_DIV     :: "cslv3.div"
OP_MOD     :: "cslv3.mod"
OP_EQ      :: "cslv3.eq"
OP_NEQ     :: "cslv3.neq"
OP_LT      :: "cslv3.lt"
OP_LE      :: "cslv3.le"
OP_GT      :: "cslv3.gt"
OP_GE      :: "cslv3.ge"
OP_AND     :: "cslv3.and"
OP_OR      :: "cslv3.or"
OP_NOT     :: "cslv3.not"
OP_IF      :: "cslv3.if"
OP_WHILE   :: "cslv3.while"
OP_FOR     :: "cslv3.for"
OP_BREAK   :: "cslv3.break"
OP_CONT    :: "cslv3.continue"
OP_CALL    :: "cslv3.call"
OP_MORPH   :: "cslv3.morpheme.tag"
OP_REFINE  :: "cslv3.refinement.assert"
OP_COMP_OF      :: "cslv3.compound.of"
OP_COMP_AND     :: "cslv3.compound.and"
OP_COMP_THAT_IS :: "cslv3.compound.that_is"
OP_COMP_HAVING  :: "cslv3.compound.having"
OP_COMP_AT      :: "cslv3.compound.at"
OP_EFF_PERFORM  :: "cslv3.effect.perform"
OP_EFF_HANDLE   :: "cslv3.effect.handle"

// ---------- Short helpers : binop-ops by name ----------

ir_op_is_binop :: proc(name: string) -> bool {
    switch name {
    case OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD,
         OP_EQ, OP_NEQ, OP_LT, OP_LE, OP_GT, OP_GE,
         OP_AND, OP_OR:
        return true
    }
    return false
}

ir_binop_result_ty :: proc(name: string, lhs_ty, rhs_ty: ^Type) -> ^Type {
    switch name {
    case OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD:
        return lhs_ty   // numeric : result = operand type
    case OP_EQ, OP_NEQ, OP_LT, OP_LE, OP_GT, OP_GE, OP_AND, OP_OR:
        return t_prim(.Bool)
    }
    return lhs_ty
}

// ---------- Attr rendering (short-form) ----------

attr_repr :: proc(a: Attr) -> string {
    switch a.kind {
    case .Int:    return fmt.tprintf("%d", a.int_v)
    case .Float:  return fmt.tprintf("%g", a.float_v)
    case .Str:    return fmt.tprintf(`"%s"`, a.str_v)
    case .Bool:   return a.bool_v ? "true" : "false"
    case .Symbol: return fmt.tprintf("@%s", a.str_v)
    case .Label:  return fmt.tprintf("^%s", a.str_v)
    case .Type:   return type_repr(a.ty_v)
    case .Sig:    return a.str_v
    }
    return "?"
}
