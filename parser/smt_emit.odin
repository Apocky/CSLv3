package cslparser

// § CSLv3 SMT-LIB2 EMITTER (T26.b Session-7)
// I> Smt_Script → deterministic SMT-LIB2 text
// I> deterministic-output : decls + options emitted in sorted-key order
// I> proof-cache-key = hash(canonical-emit) ← determinism REQUIRED
// I> layout : (set-logic ...)  (set-option ...)*  (declare-sort ...)*
//             (declare-const ...|declare-fun ...)*  (assert ...)+
//             (check-sat)  [(get-model)] [(get-unsat-core)]
// R! ← SMT-LIB2-v2.6 spec  (Barrett/Fontaine/Tinelli 2017)

import "core:fmt"
import "core:slice"
import "core:strings"

// ---------- Public entry ----------

emit_script :: proc(s: ^Smt_Script) -> string {
    sb := strings.builder_make()
    emit_script_into(&sb, s)
    return strings.to_string(sb)
}

emit_script_into :: proc(sb: ^strings.Builder, s: ^Smt_Script) {
    if s == nil {
        strings.write_string(sb, "(check-sat)\n")
        return
    }
    // 1. set-logic
    strings.write_string(sb, fmt.tprintf("(set-logic %s)\n", theory_logic_name(s.logic)))

    // 2. option : produce-models + produce-unsat-cores first (alphabetical)
    if s.produce_models {
        strings.write_string(sb, "(set-option :produce-models true)\n")
    }
    if s.produce_unsat_cores {
        strings.write_string(sb, "(set-option :produce-unsat-cores true)\n")
    }
    // 3. user-options : sorted by key
    if len(s.options) > 0 {
        keys := make([dynamic]string, 0, len(s.options))
        defer delete(keys)
        for k in s.options do append(&keys, k)
        slice.sort(keys[:])
        for k in keys {
            strings.write_string(sb, fmt.tprintf("(set-option :%s %s)\n", k, s.options[k]))
        }
    }

    // 4. declare-sort (sorted)
    if len(s.sort_decls) > 0 {
        sorted_sorts := make([dynamic]string, 0, len(s.sort_decls))
        defer delete(sorted_sorts)
        for n in s.sort_decls do append(&sorted_sorts, n)
        slice.sort(sorted_sorts[:])
        for n in sorted_sorts {
            strings.write_string(sb, fmt.tprintf("(declare-sort %s 0)\n", n))
        }
    }

    // 5. declare-const / declare-fun : sorted by name
    if len(s.decls) > 0 {
        keys := make([dynamic]string, 0, len(s.decls))
        defer delete(keys)
        for k in s.decls do append(&keys, k)
        slice.sort(keys[:])
        for k in keys {
            d := s.decls[k]
            if d.is_const {
                strings.write_string(sb, fmt.tprintf("(declare-const %s %s)\n",
                    d.name, sort_repr(d.ret)))
            } else {
                strings.write_string(sb, fmt.tprintf("(declare-fun %s (", d.name))
                for as, i in d.arg_sorts {
                    if i > 0 do strings.write_byte(sb, ' ')
                    strings.write_string(sb, sort_repr(as))
                }
                strings.write_string(sb, fmt.tprintf(") %s)\n", sort_repr(d.ret)))
            }
        }
    }

    // 6. assertions (order-preserved — order is semantically meaningful)
    for a in s.asserts {
        strings.write_string(sb, "(assert ")
        emit_formula(sb, a)
        strings.write_string(sb, ")\n")
    }

    // 7. check-sat + optional model/core
    strings.write_string(sb, "(check-sat)\n")
    if s.get_model {
        strings.write_string(sb, "(get-model)\n")
    }
    if s.produce_unsat_cores {
        strings.write_string(sb, "(get-unsat-core)\n")
    }
}

// ---------- Formula emitter ----------

emit_formula :: proc(sb: ^strings.Builder, f: ^Formula) {
    if f == nil {
        strings.write_string(sb, "false")
        return
    }
    switch f.kind {
    case .Var:
        strings.write_string(sb, f.name)

    case .BoolC:
        strings.write_string(sb, f.b_val ? "true" : "false")

    case .IntC:
        if f.i_val < 0 {
            strings.write_string(sb, fmt.tprintf("(- %d)", -f.i_val))
        } else {
            strings.write_string(sb, fmt.tprintf("%d", f.i_val))
        }

    case .RealC:
        if f.r_den == 1 {
            if f.r_num < 0 {
                strings.write_string(sb, fmt.tprintf("(- %d.0)", -f.r_num))
            } else {
                strings.write_string(sb, fmt.tprintf("%d.0", f.r_num))
            }
        } else {
            strings.write_string(sb, fmt.tprintf("(/ %d.0 %d.0)", f.r_num, f.r_den))
        }

    case .BvC:
        strings.write_string(sb, fmt.tprintf("(_ bv%d %d)", f.i_val, f.bv_width))

    case .Apply:
        if len(f.args) == 0 {
            strings.write_string(sb, f.op)
            return
        }
        strings.write_byte(sb, '(')
        strings.write_string(sb, f.op)
        for a in f.args {
            strings.write_byte(sb, ' ')
            emit_formula(sb, a)
        }
        strings.write_byte(sb, ')')

    case .Ite:
        strings.write_string(sb, "(ite ")
        emit_formula(sb, f.cond) ; strings.write_byte(sb, ' ')
        emit_formula(sb, f.th)   ; strings.write_byte(sb, ' ')
        emit_formula(sb, f.el)   ; strings.write_byte(sb, ')')

    case .Let:
        strings.write_string(sb, "(let (")
        for lb, i in f.let_bindings {
            if i > 0 do strings.write_byte(sb, ' ')
            strings.write_byte(sb, '(')
            strings.write_string(sb, lb.name)
            strings.write_byte(sb, ' ')
            emit_formula(sb, lb.expr)
            strings.write_byte(sb, ')')
        }
        strings.write_string(sb, ") ")
        emit_formula(sb, f.body)
        strings.write_byte(sb, ')')

    case .Quant:
        strings.write_byte(sb, '(')
        strings.write_string(sb, f.quant_kind == .Forall ? "forall" : "exists")
        strings.write_string(sb, " (")
        for b, i in f.quant_vars {
            if i > 0 do strings.write_byte(sb, ' ')
            strings.write_string(sb, fmt.tprintf("(%s %s)", b.name, sort_repr(b.sort)))
        }
        strings.write_string(sb, ") ")
        if len(f.triggers) > 0 {
            strings.write_string(sb, "(! ")
            emit_formula(sb, f.body)
            for t in f.triggers {
                strings.write_string(sb, " :pattern (")
                for p, i in t {
                    if i > 0 do strings.write_byte(sb, ' ')
                    emit_formula(sb, p)
                }
                strings.write_byte(sb, ')')
            }
            strings.write_byte(sb, ')')
        } else {
            emit_formula(sb, f.body)
        }
        strings.write_byte(sb, ')')
    }
}

// ---------- Canonical (deterministic) form for cache-keying ----------
// Produces the SAME byte-sequence for scripts that differ only by
// declaration/option ordering. This is what proof-cache hashes.
//
// Invariants enforced :
//   - logic + produce-models + produce-unsat-cores emitted first
//   - options sorted by key
//   - sort-decls sorted
//   - decls sorted by name
//   - assertions preserved in their user-provided order
//
// `emit_script` already satisfies these — so canonical = emit_script output.

canonical_emit :: proc(s: ^Smt_Script) -> string {
    // For now, canonical == standard emit. If we later add non-determinism
    // (e.g. auto-generated var names based on ptr-identity), the canonical
    // pass will alpha-rename here.
    return emit_script(s)
}
