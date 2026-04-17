package cslparser

// § CSLv3 EMIT-MIR BACKEND (T28.1 Session-10)
// I> CSSLv3-MIR textual : MLIR-flavor w/ cssl.* dialect ops
// I> op-mapping table : cslv3.* → cssl.* per bridge-spec (specs/14)
// I> attr-preservation : morphemes + refinements + effect-rows
// I> schema : emit_schema/mir-v1.json (see MIR_SCHEMA_TEXT below)
// I> consumer : CSSLv3-compiler via cssllint-JSON-equivalent backend

import "core:fmt"
import "core:slice"
import "core:strings"

MIR_SCHEMA_TEXT :: `{
  "$schema":     "https://json-schema.org/draft/2020-12/schema",
  "$id":         "https://cslv3.apocky/schemas/mir-v1.json",
  "title":       "CSLv3 MIR Export (mir-v1)",
  "description": "Textual MLIR-flavor IR for CSSLv3-compiler consumption.",
  "format":      "text/mir",
  "dialect":     "cssl",
  "version":     "v1",
  "opMapping":   {
    "cslv3.fn":               "cssl.fn",
    "cslv3.return":           "cssl.return",
    "cslv3.const":            "cssl.const",
    "cslv3.var_ref":          "cssl.var_ref",
    "cslv3.record":           "cssl.record",
    "cslv3.proj":             "cssl.proj",
    "cslv3.variant":          "cssl.variant",
    "cslv3.match":            "cssl.match",
    "cslv3.add":              "cssl.arith.add",
    "cslv3.sub":              "cssl.arith.sub",
    "cslv3.mul":              "cssl.arith.mul",
    "cslv3.div":              "cssl.arith.div",
    "cslv3.mod":              "cssl.arith.mod",
    "cslv3.eq":               "cssl.cmp.eq",
    "cslv3.neq":              "cssl.cmp.neq",
    "cslv3.lt":               "cssl.cmp.lt",
    "cslv3.le":               "cssl.cmp.le",
    "cslv3.gt":               "cssl.cmp.gt",
    "cslv3.ge":               "cssl.cmp.ge",
    "cslv3.and":              "cssl.logic.and",
    "cslv3.or":               "cssl.logic.or",
    "cslv3.not":              "cssl.logic.not",
    "cslv3.if":               "cssl.cf.if",
    "cslv3.while":            "cssl.cf.while",
    "cslv3.for":              "cssl.cf.for",
    "cslv3.break":            "cssl.cf.break",
    "cslv3.continue":         "cssl.cf.continue",
    "cslv3.call":             "cssl.call",
    "cslv3.morpheme.tag":     "cssl.morph.tag",
    "cslv3.refinement.assert":"cssl.refine.assert",
    "cslv3.compound.of":      "cssl.compound.of",
    "cslv3.compound.and":     "cssl.compound.and",
    "cslv3.compound.that_is": "cssl.compound.that_is",
    "cslv3.compound.having":  "cssl.compound.having",
    "cslv3.compound.at":      "cssl.compound.at",
    "cslv3.effect.perform":   "cssl.effect.perform",
    "cslv3.effect.handle":    "cssl.effect.handle"
  }
}`

emit_mir :: proc(ctx: ^Emit_Context) -> string {
    sb := strings.builder_make()
    strings.write_string(&sb, "// schema: mir-v1\n")
    strings.write_string(&sb, "// dialect: cssl\n")
    strings.write_string(&sb, fmt.tprintf("// source: %s\n", ctx.source_file))
    strings.write_string(&sb, fmt.tprintf("// emittedAt: %s\n\n", time_now_iso8601()))

    if ctx.ir_module == nil {
        strings.write_string(&sb, "cssl.module { }\n")
        return strings.to_string(sb)
    }

    strings.write_string(&sb, "cssl.module")
    if ctx.ir_module.source_file != "" {
        strings.write_string(&sb, fmt.tprintf(" @%q", ctx.ir_module.source_file))
    }
    strings.write_string(&sb, " {\n")
    for op in ctx.ir_module.ops {
        emit_mir_op(&sb, op, 1)
    }
    strings.write_string(&sb, "}\n")
    return strings.to_string(sb)
}

@(private="file")
cslv3_to_cssl :: proc(name: string) -> string {
    switch name {
    case OP_FN:             return "cssl.fn"
    case OP_RETURN:         return "cssl.return"
    case OP_CONST:          return "cssl.const"
    case OP_VAR_REF:        return "cssl.var_ref"
    case OP_RECORD:         return "cssl.record"
    case OP_PROJ:           return "cssl.proj"
    case OP_VARIANT:        return "cssl.variant"
    case OP_MATCH:          return "cssl.match"
    case OP_ADD:            return "cssl.arith.add"
    case OP_SUB:            return "cssl.arith.sub"
    case OP_MUL:            return "cssl.arith.mul"
    case OP_DIV:            return "cssl.arith.div"
    case OP_MOD:            return "cssl.arith.mod"
    case OP_EQ:             return "cssl.cmp.eq"
    case OP_NEQ:            return "cssl.cmp.neq"
    case OP_LT:             return "cssl.cmp.lt"
    case OP_LE:             return "cssl.cmp.le"
    case OP_GT:             return "cssl.cmp.gt"
    case OP_GE:             return "cssl.cmp.ge"
    case OP_AND:            return "cssl.logic.and"
    case OP_OR:             return "cssl.logic.or"
    case OP_NOT:            return "cssl.logic.not"
    case OP_IF:             return "cssl.cf.if"
    case OP_WHILE:          return "cssl.cf.while"
    case OP_FOR:            return "cssl.cf.for"
    case OP_BREAK:          return "cssl.cf.break"
    case OP_CONT:           return "cssl.cf.continue"
    case OP_CALL:           return "cssl.call"
    case OP_MORPH:          return "cssl.morph.tag"
    case OP_REFINE:         return "cssl.refine.assert"
    case OP_COMP_OF:        return "cssl.compound.of"
    case OP_COMP_AND:       return "cssl.compound.and"
    case OP_COMP_THAT_IS:   return "cssl.compound.that_is"
    case OP_COMP_HAVING:    return "cssl.compound.having"
    case OP_COMP_AT:        return "cssl.compound.at"
    case OP_EFF_PERFORM:    return "cssl.effect.perform"
    case OP_EFF_HANDLE:     return "cssl.effect.handle"
    case "cslv3.branch":    return "cssl.cf.branch"
    case "cslv3.cond_branch": return "cssl.cf.cond_branch"
    case "cslv3.yield":     return "cssl.yield"
    }
    // unknown cslv3.*  → prefix-swap if it starts with "cslv3."
    if strings.has_prefix(name, "cslv3.") {
        return fmt.tprintf("cssl.%s", name[len("cslv3."):])
    }
    return name
}

@(private="file")
emit_mir_op :: proc(sb: ^strings.Builder, op: ^Op, indent: int) {
    if op == nil do return
    write_indent_mir(sb, indent)

    if len(op.results) > 0 {
        for r, i in op.results {
            if i > 0 do strings.write_string(sb, ", ")
            write_value_mir(sb, r)
        }
        strings.write_string(sb, " = ")
    }
    strings.write_string(sb, cslv3_to_cssl(op.name))

    if len(op.operands) > 0 {
        strings.write_byte(sb, '(')
        for o, i in op.operands {
            if i > 0 do strings.write_string(sb, ", ")
            write_value_mir(sb, o)
        }
        strings.write_byte(sb, ')')
    }

    if len(op.attrs) > 0 {
        strings.write_string(sb, " {")
        keys := make([dynamic]string, 0, len(op.attrs))
        defer delete(keys)
        for k in op.attrs do append(&keys, k)
        slice.sort(keys[:])
        for k, i in keys {
            if i > 0 do strings.write_string(sb, ", ")
            strings.write_string(sb, k)
            strings.write_byte(sb, '=')
            strings.write_string(sb, attr_repr(op.attrs[k]))
        }
        strings.write_byte(sb, '}')
    }

    if len(op.results) > 0 {
        strings.write_string(sb, " : ")
        for r, i in op.results {
            if i > 0 do strings.write_string(sb, ", ")
            strings.write_string(sb, type_repr(r.ty))
        }
    }

    if len(op.regions) > 0 {
        strings.write_string(sb, " ")
        for r, i in op.regions {
            if i > 0 do strings.write_string(sb, ", ")
            emit_mir_region(sb, r, indent)
        }
    }

    strings.write_byte(sb, '\n')
}

@(private="file")
emit_mir_region :: proc(sb: ^strings.Builder, r: ^Region, indent: int) {
    if r == nil {
        strings.write_string(sb, "{}")
        return
    }
    strings.write_string(sb, "{\n")
    for b in r.blocks {
        emit_mir_block(sb, b, indent + 1)
    }
    write_indent_mir(sb, indent)
    strings.write_byte(sb, '}')
}

@(private="file")
emit_mir_block :: proc(sb: ^strings.Builder, b: ^Block, indent: int) {
    if b == nil do return
    write_indent_mir(sb, indent)
    strings.write_byte(sb, '^')
    strings.write_string(sb, b.label)
    if len(b.args) > 0 {
        strings.write_byte(sb, '(')
        for a, i in b.args {
            if i > 0 do strings.write_string(sb, ", ")
            write_value_mir(sb, a)
            strings.write_string(sb, " : ")
            strings.write_string(sb, type_repr(a.ty))
        }
        strings.write_byte(sb, ')')
    }
    strings.write_string(sb, ":\n")
    for op in b.ops do emit_mir_op(sb, op, indent + 1)
}

@(private="file")
write_value_mir :: proc(sb: ^strings.Builder, v: ^Value) {
    if v == nil {
        strings.write_string(sb, "%<nil>")
        return
    }
    strings.write_string(sb, fmt.tprintf("%%%d", v.id))
    if v.name != "" do strings.write_string(sb, fmt.tprintf(":%s", v.name))
}

@(private="file")
write_indent_mir :: proc(sb: ^strings.Builder, n: int) {
    for _ in 0..<n do strings.write_string(sb, "  ")
}
