package cslparser

import "core:fmt"
import "core:strings"

// § CSLv3 PARSER — AST NODE DEFINITIONS
// I> unified Node type — discriminated by Node_Kind
// W! slot template preserved: evidence, modal, det, subject, relation, object, gate, scope, meta
// W! compound formation preserved via Compound_Expr w/ op ∈ {. + - ⊗ @}
// I> children[] holds tree; gate/scope/type_expr/meta are named slots

Node_Kind :: enum {
    // --- document structure ---
    Document,
    Section,
    Block,

    // --- statement forms ---
    Definition,        // subject : type = expr  (or subject = expr)
    Relation,          // subject <rel> object (:: → ⇒ ∈ ⊂ ≡ ↔ ←)
    Constraint,        // ⌈ expr ⌉
    Precondition,      // ⌊ expr ⌋
    Conditional,       // expr ? then : else   OR   cond → result
    Flow,              // X → Y   (standalone)
    Formula,           // ⟦ ... ⟧
    Directive,         // standalone modal prose line
    Function_Def,      // fn name(params) → ret { body }
    Type_Def,          // def name ⟨fields⟩
    Enum_Def,          // def name = enum[variants]
    Match_Stmt,
    Axiom,             // t∞: expr
    Alias_Def,         // alias short = long
    Import,            // use §module.name
    Export,            // pub name
    ForAll_Stmt,       // ∀ x ∈ xs: block
    Exists_Stmt,       // ∃ x: expr
    Expr_Stmt,
    Comment,

    // --- expressions ---
    Ident,
    Compound_Expr,     // compound op: . + - ⊗ @
    Binary,            // arithmetic / comparison / logic
    Unary,
    Call,
    Pipeline,
    Lambda,
    Index,
    Tuple_Expr,
    List_Expr,
    Group,             // ( ... )
    PosRef,            // $0 $1 $2
    Record_Expr,       // ⟨ field=val, ... ⟩

    // --- literals ---
    Num_Lit,
    Str_Lit,
    Bool_Lit,
    Nil_Lit,

    // --- types ---
    Type_Prim,
    Type_Ident,
    Type_Array,        // [T;N]
    Type_Union,        // T | U
    Type_Opt,          // T?
    Type_Result,       // T!
    Type_Tuple,        // (T, U, V)
    Type_Map,          // {K: V}
    Type_Ref,          // &T
    Type_Linear,       // T!lin
    Type_Mut_Ref,      // &mut T
    Type_Refinement,   // { x:T ⊢ P(x) }
    Type_Pi,           // Π⟨x:T⟩ → U(x)
    Type_Sigma,        // Σ⟨x:T, y:U⟩
    Type_Record,       // ⟨f:T, ...⟩

    // --- helpers ---
    Field_Decl,
    Variant_Decl,
    Param_Decl,
    Gate_Clause,
    Scope_Clause,
    Match_Arm,
    Suffix_Chain,      // morpheme stack: base.prog.cert ...
}

Node :: struct {
    kind:      Node_Kind,
    pos:       Source_Pos,

    // --- slot-template metadata (applicable on statements) ---
    evidence:  Token_Kind,    // .Invalid when absent (default ✓)
    modal:     Token_Kind,    // .Invalid when absent (default assertion)
    det:       Token_Kind,    // domain determinative (§ ∫ ⊞) or .Invalid
    suffix:    Token_Kind,    // type suffix ('d 'f 's ...) or .Invalid

    // --- generic payloads ---
    text:      string,        // name / section-header / literal source
    op:        Token_Kind,    // operator (for Binary, Unary, Relation, Compound_Expr)
    int_val:   i64,
    float_val: f64,
    bool_val:  bool,
    is_float:  bool,

    // --- children (tree structure; role determined by kind) ---
    children:  [dynamic]^Node,

    // --- named slots (optional) ---
    gate:      ^Node,         // Gate_Clause
    scope:     ^Node,         // Scope_Clause
    type_expr: ^Node,          // attached type annotation
    constraint: ^Node,          // attached constraint ⌈ ⌉
    meta:      string,        // trailing # comment text

    // --- morpheme stacking ---
    morphemes: [dynamic]string, // .prog .cert .must .loc etc

    // --- T23 (Session-5) comment preservation ---
    // Leading comments attached to this statement / field / definition.
    // Populated by the parser when `emit_comments = true` (default).
    // Pprint emits them before the node body.
    comments_before: [dynamic]string,
}

// === Node construction helpers ===

make_node :: proc(kind: Node_Kind, pos: Source_Pos) -> ^Node {
    n := new(Node)
    n.kind = kind
    n.pos = pos
    n.evidence = .Invalid
    n.modal = .Invalid
    n.det = .Invalid
    n.suffix = .Invalid
    n.op = .Invalid
    n.children = make([dynamic]^Node)
    n.morphemes = make([dynamic]string)
    n.comments_before = make([dynamic]string)
    return n
}

node_add_child :: proc(parent: ^Node, child: ^Node) {
    if child != nil do append(&parent.children, child)
}

node_destroy :: proc(n: ^Node) {
    if n == nil do return
    for c in n.children do node_destroy(c)
    node_destroy(n.gate)
    node_destroy(n.scope)
    node_destroy(n.type_expr)
    node_destroy(n.constraint)
    delete(n.children)
    delete(n.morphemes)
    delete(n.comments_before)
    free(n)
}

// === Pretty-printer (S-expression style) ===

ast_sprint :: proc(n: ^Node, indent: int = 0, sb: ^strings.Builder) {
    if n == nil {
        pad(sb, indent)
        strings.write_string(sb, "<nil>\n")
        return
    }
    pad(sb, indent)
    strings.write_rune(sb, '(')
    strings.write_string(sb, kind_name(n.kind))

    // slot metadata
    if n.evidence != .Invalid {
        strings.write_string(sb, " evidence=")
        strings.write_string(sb, token_kind_name(n.evidence))
    }
    if n.modal != .Invalid {
        strings.write_string(sb, " modal=")
        strings.write_string(sb, token_kind_name(n.modal))
    }
    if n.det != .Invalid {
        strings.write_string(sb, " det=")
        strings.write_string(sb, token_kind_name(n.det))
    }
    if n.suffix != .Invalid {
        strings.write_string(sb, " suffix=")
        strings.write_string(sb, token_kind_name(n.suffix))
    }
    if n.op != .Invalid {
        strings.write_string(sb, " op=")
        strings.write_string(sb, token_kind_name(n.op))
    }
    if len(n.text) > 0 {
        strings.write_string(sb, " text=\"")
        strings.write_string(sb, n.text)
        strings.write_rune(sb, '"')
    }
    if n.kind == .Num_Lit {
        if n.is_float {
            strings.write_string(sb, fmt.tprintf(" float=%v", n.float_val))
        } else {
            strings.write_string(sb, fmt.tprintf(" int=%d", n.int_val))
        }
    }
    if n.kind == .Bool_Lit {
        strings.write_string(sb, fmt.tprintf(" bool=%v", n.bool_val))
    }
    if len(n.morphemes) > 0 {
        strings.write_string(sb, " morph=[")
        for m, i in n.morphemes {
            if i > 0 do strings.write_string(sb, ",")
            strings.write_string(sb, m)
        }
        strings.write_rune(sb, ']')
    }
    if len(n.meta) > 0 {
        strings.write_string(sb, " meta=\"")
        strings.write_string(sb, n.meta)
        strings.write_rune(sb, '"')
    }

    // children + slots
    has_children := len(n.children) > 0 || n.gate != nil || n.scope != nil || n.type_expr != nil || n.constraint != nil
    if has_children {
        strings.write_rune(sb, '\n')
        if n.type_expr != nil {
            pad(sb, indent+2)
            strings.write_string(sb, ":type\n")
            ast_sprint(n.type_expr, indent+4, sb)
        }
        if n.constraint != nil {
            pad(sb, indent+2)
            strings.write_string(sb, ":constraint\n")
            ast_sprint(n.constraint, indent+4, sb)
        }
        if n.gate != nil {
            pad(sb, indent+2)
            strings.write_string(sb, ":gate\n")
            ast_sprint(n.gate, indent+4, sb)
        }
        if n.scope != nil {
            pad(sb, indent+2)
            strings.write_string(sb, ":scope\n")
            ast_sprint(n.scope, indent+4, sb)
        }
        for c in n.children {
            ast_sprint(c, indent+2, sb)
        }
        pad(sb, indent)
        strings.write_string(sb, ")\n")
    } else {
        strings.write_string(sb, ")\n")
    }
}

@(private="file")
pad :: proc(sb: ^strings.Builder, n: int) {
    for _ in 0 ..< n do strings.write_rune(sb, ' ')
}

kind_name :: proc(k: Node_Kind) -> string {
    switch k {
    case .Document:         return "Document"
    case .Section:          return "Section"
    case .Block:            return "Block"
    case .Definition:       return "Definition"
    case .Relation:         return "Relation"
    case .Constraint:       return "Constraint"
    case .Precondition:     return "Precondition"
    case .Conditional:      return "Conditional"
    case .Flow:             return "Flow"
    case .Formula:          return "Formula"
    case .Directive:        return "Directive"
    case .Function_Def:     return "FnDef"
    case .Type_Def:         return "TypeDef"
    case .Enum_Def:         return "EnumDef"
    case .Match_Stmt:       return "Match"
    case .Axiom:            return "Axiom"
    case .Alias_Def:        return "Alias"
    case .Import:           return "Import"
    case .Export:           return "Export"
    case .ForAll_Stmt:      return "ForAll"
    case .Exists_Stmt:      return "Exists"
    case .Expr_Stmt:        return "ExprStmt"
    case .Comment:          return "Comment"
    case .Ident:            return "Ident"
    case .Compound_Expr:    return "Compound"
    case .Binary:           return "Binary"
    case .Unary:            return "Unary"
    case .Call:             return "Call"
    case .Pipeline:         return "Pipeline"
    case .Lambda:           return "Lambda"
    case .Index:            return "Index"
    case .Tuple_Expr:       return "Tuple"
    case .List_Expr:        return "List"
    case .Group:            return "Group"
    case .PosRef:           return "PosRef"
    case .Record_Expr:      return "Record"
    case .Num_Lit:          return "Num"
    case .Str_Lit:          return "Str"
    case .Bool_Lit:         return "Bool"
    case .Nil_Lit:          return "Nil"
    case .Type_Prim:        return "TyPrim"
    case .Type_Ident:       return "TyIdent"
    case .Type_Array:       return "TyArray"
    case .Type_Union:       return "TyUnion"
    case .Type_Opt:         return "TyOpt"
    case .Type_Result:      return "TyResult"
    case .Type_Tuple:       return "TyTuple"
    case .Type_Map:         return "TyMap"
    case .Type_Ref:         return "TyRef"
    case .Type_Linear:      return "TyLinear"
    case .Type_Mut_Ref:     return "TyMutRef"
    case .Type_Refinement:  return "TyRefine"
    case .Type_Pi:          return "TyPi"
    case .Type_Sigma:       return "TySigma"
    case .Type_Record:      return "TyRecord"
    case .Field_Decl:       return "Field"
    case .Variant_Decl:     return "Variant"
    case .Param_Decl:       return "Param"
    case .Gate_Clause:      return "Gate"
    case .Scope_Clause:     return "Scope"
    case .Match_Arm:        return "Arm"
    case .Suffix_Chain:     return "SuffixChain"
    }
    return "?"
}
