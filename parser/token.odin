package cslparser

// § CSLv3 TOKEN DEFINITIONS
// I> unified token kind enum covering all glyph classes from §01
// W! every unicode glyph also accepts its ASCII alias (§12)
// W! source positions preserved for error messages

Token_Kind :: enum {
    // --- structural ---
    Section,           // §
    Newline,
    Indent,
    Dedent,
    EOF,
    Invalid,

    // --- flow / arrows ---
    Arrow_Right,       // → ->
    Arrow_Left,        // ← <-
    Arrow_Bidi,        // ↔ <->
    Implies,           // ⇒ =>
    Entails,           // ⊢ |-
    Therefore,         // ∴ .:.
    Because,           // ∵ :..
    QED,               // ∎ QED

    // --- modals ---
    Modal_Must,        // W!
    Modal_Should,      // R!
    Modal_May,         // M?
    Modal_MustNot,     // N!
    Modal_Insight,     // I>
    Modal_Question,    // Q?
    Modal_Push,        // P>
    Modal_Decision,    // D>
    Modal_Todo,        // TODO
    Modal_Fixme,       // FIXME

    // --- evidence ---
    Ev_Confirmed,      // ✓ [x]
    Ev_Partial,        // ◐ [~]
    Ev_Pending,        // ○ [ ]
    Ev_Failed,         // ✗ [!]
    Ev_Unknown,        // ⊘ [?]
    Ev_Hypothetical,   // △ [^]
    Ev_Deprecated,     // ▽ [v]
    Ev_Proven,         // ‼ [!!]

    // --- compound ops (§03) ---
    Dot,               // .  tatpurusha
    Plus,              // +  dvandva
    Minus,             // -  karmadhāraya
    Tensor,            // ⊗ x*  bahuvrihi
    At,                // @  avyayibhava

    // --- binding / types ---
    Colon,             // :
    DoubleColon,       // ::
    Eq,                // =
    NotEq,             // != ≠
    Range,             // ..
    Ellipsis,          // ...

    // --- structural punct ---
    Pipe,              // |
    Amp,               // &
    Bang,              // !
    Question,          // ?
    Hash,              // #
    Star,              // *
    Caret,             // ^
    Underscore,        // _
    Slash,             // /
    Backslash,         // \
    Percent,           // %
    Dollar,            // $
    Comma,             // ,
    Semi,              // ;
    Tilde,             // ~

    // --- set / logic ---
    ForAll,            // ∀ all
    Exists,            // ∃ any
    In,                // ∈ in
    NotIn,             // ∉ !in
    Union,             // ∪ |+
    Intersect,         // ∩ &+
    Subset,            // ⊂ <:
    Superset,          // ⊃ :>
    Not,               // ¬  (also ~ via Tilde)
    And,               // ∧ &&
    Or,                // ∨ ||
    Xor,               // ⊕ xor
    Identical,         // ≡ ===
    Approx,            // ≈ ~=
    Gte,               // ≥ >=
    Lte,               // ≤ <=
    Gt,                // >
    Lt,                // <
    EqEq,              // ==
    Infinity,          // ∞ inf
    Empty,             // ∅
    Plus_Eq,           // +=
    Minus_Eq,          // -=
    Star_Eq,           // *=
    Slash_Eq,          // /=

    // --- enclosures ---
    LParen, RParen,         // ( )
    LBracket, RBracket,     // [ ]
    LBrace, RBrace,         // { }
    LAngle, RAngle,         // ⟨ ⟩
    LFormula, RFormula,     // ⟦ ⟧
    LQuote_Ext, RQuote_Ext, // « »
    LConstraint, RConstraint, // ⌈ ⌉
    LPre, RPre,             // ⌊ ⌋
    LTemporal, RTemporal,   // ⟪ ⟫

    // --- type suffixes (postfix) ---
    Suffix_Data,       // 'd
    Suffix_Func,       // 'f
    Suffix_System,     // 's
    Suffix_Type,       // 't
    Suffix_Entity,     // 'e
    Suffix_Material,   // 'm
    Suffix_Prop,       // 'p
    Suffix_Gate,       // 'g
    Suffix_Rule,       // 'r

    // --- domain determinatives ---
    Det_Field,         // ∫
    Det_Spatial,       // ⊞

    // --- pipeline / dataflow ---
    PipeFwd,           // |>
    PipeBack,          // <|
    Dispatch,          // >>
    Receive,           // <<
    Causes,            // ~>

    // --- temporal / math ---
    Delta,             // Δ D
    Partial,           // ∂ d/
    Nabla,             // ∇ grad
    Lambda,            // λ \ (as fn abstractor)

    // --- keywords ---
    Kw_Fn,
    Kw_Def,
    Kw_Enum,
    Kw_Let,
    Kw_Pub,
    Kw_Use,
    Kw_Alias,
    Kw_Match,
    Kw_If,
    Kw_When,
    Kw_Unless,
    Kw_While,
    Kw_Per,
    Kw_True,
    Kw_False,
    Kw_Nil,
    Kw_Pre,         // pre:
    Kw_Post,        // post:

    // --- primitive types ---
    Prim_U8, Prim_U16, Prim_U32, Prim_U64,
    Prim_I8, Prim_I16, Prim_I32, Prim_I64,
    Prim_F32, Prim_F64,
    Prim_Bool, Prim_Str,
    Prim_Vec2, Prim_Vec3, Prim_Vec4,
    Prim_Mat4, Prim_Quat, Prim_Rgba,

    // --- atoms ---
    Ident,             // identifier
    Number,            // int / float / hex / binary
    String,            // "..." or `...`
    PosRef,            // $0 $1 $2

    // --- reasoning glyphs (§05) ---
    Surprising,        // ?!
    Suspect,           // !?
    Iterate,           // ⟲ loop
    Dive,              // ⤓ vv
    Lift,              // ⤒ ^^
    Pivot,             // ⟐ <>
    Warning,           // ⚠
    KeyInsight,        // ★ *!
    NoteSelf,          // ✎ //

    // --- physics / material (tier-2) ---
    Phys_Rho,          // ρ
    Phys_Mu,           // μ
    Phys_Sigma,        // σ
    Phys_Kappa,        // κ
    Phys_Epsilon,      // ε
    Phys_LambdaPhys,   // λ used as wavelength (ambiguous w/ lambda fn — context)
    Phys_Tau,          // τ

    // --- comment (preserved for round-trip) ---
    Comment,           // # ... EOL
}

Source_Pos :: struct {
    file:   string,
    line:   int,    // 1-based
    col:    int,    // 1-based
    offset: int,    // byte offset
}

Token :: struct {
    kind:  Token_Kind,
    text:  string,        // source slice / synthesized text
    pos:   Source_Pos,
    // numeric payloads (only valid for Number)
    int_val:   i64,
    float_val: f64,
    is_float:  bool,
    // indent payload (only valid for Indent/Dedent/Newline)
    indent_level: int,
}

token_kind_name :: proc(k: Token_Kind) -> string {
    #partial switch k {
    case .Section:         return "§"
    case .Newline:         return "NEWLINE"
    case .Indent:          return "INDENT"
    case .Dedent:          return "DEDENT"
    case .EOF:             return "EOF"
    case .Invalid:         return "INVALID"
    case .Arrow_Right:     return "->"
    case .Arrow_Left:      return "<-"
    case .Arrow_Bidi:      return "<->"
    case .Implies:         return "=>"
    case .Entails:         return "|-"
    case .Therefore:       return ".:."
    case .Because:         return ":.."
    case .QED:             return "QED"
    case .Modal_Must:      return "W!"
    case .Modal_Should:    return "R!"
    case .Modal_May:       return "M?"
    case .Modal_MustNot:   return "N!"
    case .Modal_Insight:   return "I>"
    case .Modal_Question:  return "Q?"
    case .Modal_Push:      return "P>"
    case .Modal_Decision:  return "D>"
    case .Modal_Todo:      return "TODO"
    case .Modal_Fixme:     return "FIXME"
    case .Ev_Confirmed:    return "[x]"
    case .Ev_Partial:      return "[~]"
    case .Ev_Pending:      return "[ ]"
    case .Ev_Failed:       return "[!]"
    case .Ev_Unknown:      return "[?]"
    case .Ev_Hypothetical: return "[^]"
    case .Ev_Deprecated:   return "[v]"
    case .Ev_Proven:       return "[!!]"
    case .Dot:             return "."
    case .Plus:            return "+"
    case .Minus:           return "-"
    case .Tensor:          return "x*"
    case .At:              return "@"
    case .Colon:           return ":"
    case .DoubleColon:     return "::"
    case .Eq:              return "="
    case .NotEq:           return "!="
    case .Range:           return ".."
    case .Ellipsis:        return "..."
    case .Pipe:            return "|"
    case .Amp:             return "&"
    case .Bang:            return "!"
    case .Question:        return "?"
    case .Hash:            return "#"
    case .Star:            return "*"
    case .Caret:           return "^"
    case .Underscore:      return "_"
    case .Slash:           return "/"
    case .Backslash:       return "\\"
    case .Percent:         return "%"
    case .Dollar:          return "$"
    case .Comma:           return ","
    case .Semi:            return ";"
    case .Tilde:           return "~"
    case .ForAll:          return "all"
    case .Exists:          return "any"
    case .In:              return "in"
    case .NotIn:           return "!in"
    case .Union:           return "|+"
    case .Intersect:       return "&+"
    case .Subset:          return "<:"
    case .Superset:        return ":>"
    case .Not:             return "¬"
    case .And:             return "&&"
    case .Or:              return "||"
    case .Xor:             return "xor"
    case .Identical:       return "==="
    case .Approx:          return "~="
    case .Gte:             return ">="
    case .Lte:             return "<="
    case .Gt:              return ">"
    case .Lt:              return "<"
    case .EqEq:            return "=="
    case .Infinity:        return "inf"
    case .Empty:           return "nil"
    case .Plus_Eq:         return "+="
    case .Minus_Eq:        return "-="
    case .Star_Eq:         return "*="
    case .Slash_Eq:        return "/="
    case .LParen:          return "("
    case .RParen:          return ")"
    case .LBracket:        return "["
    case .RBracket:        return "]"
    case .LBrace:          return "{"
    case .RBrace:          return "}"
    case .LAngle:          return "⟨"
    case .RAngle:          return "⟩"
    case .LFormula:        return "⟦"
    case .RFormula:        return "⟧"
    case .LQuote_Ext:      return "«"
    case .RQuote_Ext:      return "»"
    case .LConstraint:     return "⌈"
    case .RConstraint:     return "⌉"
    case .LPre:            return "⌊"
    case .RPre:            return "⌋"
    case .LTemporal:       return "⟪"
    case .RTemporal:       return "⟫"
    case .Suffix_Data:     return "'d"
    case .Suffix_Func:     return "'f"
    case .Suffix_System:   return "'s"
    case .Suffix_Type:     return "'t"
    case .Suffix_Entity:   return "'e"
    case .Suffix_Material: return "'m"
    case .Suffix_Prop:     return "'p"
    case .Suffix_Gate:     return "'g"
    case .Suffix_Rule:     return "'r"
    case .Det_Field:       return "∫"
    case .Det_Spatial:     return "⊞"
    case .PipeFwd:         return "|>"
    case .PipeBack:        return "<|"
    case .Dispatch:        return ">>"
    case .Receive:         return "<<"
    case .Causes:          return "~>"
    case .Delta:           return "D"
    case .Partial:         return "d/"
    case .Nabla:           return "grad"
    case .Lambda:          return "\\"
    case .Kw_Fn:           return "fn"
    case .Kw_Def:          return "def"
    case .Kw_Enum:         return "enum"
    case .Kw_Let:          return "let"
    case .Kw_Pub:          return "pub"
    case .Kw_Use:          return "use"
    case .Kw_Alias:        return "alias"
    case .Kw_Match:        return "match"
    case .Kw_If:           return "if"
    case .Kw_When:         return "when"
    case .Kw_Unless:       return "unless"
    case .Kw_While:        return "while"
    case .Kw_Per:          return "per"
    case .Kw_True:         return "true"
    case .Kw_False:        return "false"
    case .Kw_Nil:          return "nil"
    case .Kw_Pre:          return "pre"
    case .Kw_Post:         return "post"
    case .Prim_U8:         return "u8"
    case .Prim_U16:        return "u16"
    case .Prim_U32:        return "u32"
    case .Prim_U64:        return "u64"
    case .Prim_I8:         return "i8"
    case .Prim_I16:        return "i16"
    case .Prim_I32:        return "i32"
    case .Prim_I64:        return "i64"
    case .Prim_F32:        return "f32"
    case .Prim_F64:        return "f64"
    case .Prim_Bool:       return "bool"
    case .Prim_Str:        return "str"
    case .Prim_Vec2:       return "vec2"
    case .Prim_Vec3:       return "vec3"
    case .Prim_Vec4:       return "vec4"
    case .Prim_Mat4:       return "mat4"
    case .Prim_Quat:       return "quat"
    case .Prim_Rgba:       return "rgba"
    case .Ident:           return "IDENT"
    case .Number:          return "NUMBER"
    case .String:          return "STRING"
    case .PosRef:          return "POSREF"
    case .Surprising:      return "?!"
    case .Suspect:         return "!?"
    case .Iterate:         return "loop"
    case .Dive:            return "vv"
    case .Lift:            return "^^"
    case .Pivot:           return "<>"
    case .Warning:         return "⚠"
    case .KeyInsight:      return "*!"
    case .NoteSelf:        return "//"
    case .Phys_Rho:        return "ρ"
    case .Phys_Mu:         return "μ"
    case .Phys_Sigma:      return "σ"
    case .Phys_Kappa:      return "κ"
    case .Phys_Epsilon:    return "ε"
    case .Phys_LambdaPhys: return "λ(phys)"
    case .Phys_Tau:        return "τ"
    case .Comment:         return "COMMENT"
    case:                  return "?"
    }
}

token_is_evidence :: proc(k: Token_Kind) -> bool {
    #partial switch k {
    case .Ev_Confirmed, .Ev_Partial, .Ev_Pending, .Ev_Failed,
         .Ev_Unknown, .Ev_Hypothetical, .Ev_Deprecated, .Ev_Proven:
        return true
    }
    return false
}

token_is_modal :: proc(k: Token_Kind) -> bool {
    #partial switch k {
    case .Modal_Must, .Modal_Should, .Modal_May, .Modal_MustNot,
         .Modal_Insight, .Modal_Question, .Modal_Push, .Modal_Decision,
         .Modal_Todo, .Modal_Fixme:
        return true
    }
    return false
}

token_is_suffix :: proc(k: Token_Kind) -> bool {
    #partial switch k {
    case .Suffix_Data, .Suffix_Func, .Suffix_System, .Suffix_Type,
         .Suffix_Entity, .Suffix_Material, .Suffix_Prop, .Suffix_Gate,
         .Suffix_Rule:
        return true
    }
    return false
}

token_is_primitive_type :: proc(k: Token_Kind) -> bool {
    #partial switch k {
    case .Prim_U8, .Prim_U16, .Prim_U32, .Prim_U64,
         .Prim_I8, .Prim_I16, .Prim_I32, .Prim_I64,
         .Prim_F32, .Prim_F64,
         .Prim_Bool, .Prim_Str,
         .Prim_Vec2, .Prim_Vec3, .Prim_Vec4,
         .Prim_Mat4, .Prim_Quat, .Prim_Rgba:
        return true
    }
    return false
}

token_is_keyword :: proc(k: Token_Kind) -> bool {
    #partial switch k {
    case .Kw_Fn, .Kw_Def, .Kw_Enum, .Kw_Let, .Kw_Pub, .Kw_Use,
         .Kw_Alias, .Kw_Match, .Kw_If, .Kw_When, .Kw_Unless,
         .Kw_While, .Kw_Per, .Kw_True, .Kw_False, .Kw_Nil,
         .Kw_Pre, .Kw_Post:
        return true
    }
    return false
}

token_is_relation :: proc(k: Token_Kind) -> bool {
    #partial switch k {
    case .Colon, .DoubleColon, .Eq, .EqEq, .NotEq, .Identical,
         .Arrow_Right, .Arrow_Left, .Arrow_Bidi, .Implies, .Entails,
         .In, .Subset, .Superset:
        return true
    }
    return false
}
