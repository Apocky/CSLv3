package cslparser

// § CSLv3 IR PRINTER (T21.d Session-6)
// I> textual MLIR-flavor dump for round-trip debug + golden-diff
// I> format :
//    module {
//      %1 = cslv3.fn @name : (i32) -> i32 {
//        ^entry(%2: i32):
//          %3 = cslv3.const {value=0} : i32
//          cslv3.return %3 : i32
//      }
//    }
// I> attrs : rendered as {key=value, key=value} sorted-by-key for determinism
// I> values : %N form (N = Value.id) ; %N:label for block-args ; Types via type_repr
// R! ← MLIR-textual-format (regions = braces, blocks = ^label:, values = %id)

import "core:fmt"
import "core:slice"
import "core:strings"

// ---------- Public entry ----------

ir_print_module :: proc(m: ^Module) -> string {
    sb := strings.builder_make()
    print_module(&sb, m)
    return strings.to_string(sb)
}

// ---------- Module ----------

@(private="file")
print_module :: proc(sb: ^strings.Builder, m: ^Module) {
    if m == nil {
        strings.write_string(sb, "module {}\n")
        return
    }
    strings.write_string(sb, "module")
    if m.source_file != "" {
        strings.write_string(sb, fmt.tprintf(" @%q", m.source_file))
    }
    strings.write_string(sb, " {\n")
    for op in m.ops {
        print_op(sb, op, 1)
    }
    strings.write_string(sb, "}\n")
}

// ---------- Op ----------

@(private="file")
print_op :: proc(sb: ^strings.Builder, op: ^Op, indent: int) {
    if op == nil do return
    write_indent(sb, indent)
    // Results : %N[, %N]* = name ...
    if len(op.results) > 0 {
        for r, i in op.results {
            if i > 0 do strings.write_string(sb, ", ")
            write_value_ref(sb, r)
        }
        strings.write_string(sb, " = ")
    }
    strings.write_string(sb, op.name)

    // Operands
    if len(op.operands) > 0 {
        strings.write_byte(sb, '(')
        for o, i in op.operands {
            if i > 0 do strings.write_string(sb, ", ")
            write_value_ref(sb, o)
        }
        strings.write_byte(sb, ')')
    }

    // Attrs (sorted keys)
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

    // Result types
    if len(op.results) > 0 {
        strings.write_string(sb, " : ")
        for r, i in op.results {
            if i > 0 do strings.write_string(sb, ", ")
            strings.write_string(sb, type_repr(r.ty))
        }
    }

    // Regions
    if len(op.regions) > 0 {
        strings.write_string(sb, " ")
        for r, i in op.regions {
            if i > 0 do strings.write_string(sb, ", ")
            print_region(sb, r, indent)
        }
    }

    strings.write_byte(sb, '\n')
}

// ---------- Region / Block ----------

@(private="file")
print_region :: proc(sb: ^strings.Builder, r: ^Region, indent: int) {
    if r == nil {
        strings.write_string(sb, "{}")
        return
    }
    strings.write_string(sb, "{")
    if r.kind != .Generic {
        strings.write_string(sb, fmt.tprintf("  // kind=%v", r.kind))
    }
    strings.write_byte(sb, '\n')
    for b in r.blocks {
        print_block(sb, b, indent + 1)
    }
    write_indent(sb, indent)
    strings.write_byte(sb, '}')
}

@(private="file")
print_block :: proc(sb: ^strings.Builder, b: ^Block, indent: int) {
    if b == nil do return
    write_indent(sb, indent)
    strings.write_byte(sb, '^')
    strings.write_string(sb, b.label)

    if len(b.args) > 0 {
        strings.write_byte(sb, '(')
        for a, i in b.args {
            if i > 0 do strings.write_string(sb, ", ")
            write_value_ref(sb, a)
            strings.write_string(sb, " : ")
            strings.write_string(sb, type_repr(a.ty))
        }
        strings.write_byte(sb, ')')
    }

    strings.write_string(sb, ":\n")
    for op in b.ops {
        print_op(sb, op, indent + 1)
    }
}

// ---------- Helpers ----------

@(private="file")
write_value_ref :: proc(sb: ^strings.Builder, v: ^Value) {
    if v == nil {
        strings.write_string(sb, "%<nil>")
        return
    }
    strings.write_string(sb, fmt.tprintf("%%%d", v.id))
    if v.name != "" {
        strings.write_string(sb, fmt.tprintf(":%s", v.name))
    }
}

@(private="file")
write_indent :: proc(sb: ^strings.Builder, indent: int) {
    for _ in 0..<indent do strings.write_string(sb, "  ")
}

