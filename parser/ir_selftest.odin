package cslparser

// § CSLv3 IR-VERIFIER SELF-TEST (T21.g Session-6)
// I> deliberately-malformed modules exercise each invariant-class ;
// I> CLI invocation : `parser --ir-selftest`
// I> Python harness asserts "CASE N: PASS" appears for every case.
// R! ← MLIR unit-test pattern ; we fabricate IR directly rather than
//      try to coax lower.odin into producing broken IR.

import "core:fmt"

ir_selftest_main :: proc() {
    total := 0
    pass  := 0

    // ---- CASE 1 : missing terminator ----
    total += 1
    {
        ir_reset_ids()
        m := new_module("case1")
        fn := new_op(OP_FN)
        op_set_attr(fn, "name", attr_symbol("case1"))
        op_set_attr(fn, "sig",  attr_type(t_arrow(t_unit(), t_unit())))
        r := new_region(fn, .Fn_Body)
        op_add_region(fn, r)
        b := new_block("entry", r)
        region_add_block(r, b)
        // deliberately : no terminator in block
        dummy := new_op(OP_CONST)
        op_set_attr(dummy, "value", attr_int(0))
        op_add_result(dummy, t_prim(.I32))
        block_append_op(b, dummy)
        module_append_op(m, fn)

        res := ir_verify(m)
        defer ir_verify_result_destroy(&res)
        if has_code(&res, .Ir_Missing_Terminator) {
            fmt.println("CASE 1: PASS missing-terminator")
            pass += 1
        } else {
            fmt.println("CASE 1: FAIL expected Ir_Missing_Terminator")
            dump_diags(&res)
        }
    }

    // ---- CASE 2 : use-before-def ----
    total += 1
    {
        ir_reset_ids()
        m := new_module("case2")
        fn := new_op(OP_FN)
        op_set_attr(fn, "name", attr_symbol("case2"))
        op_set_attr(fn, "sig",  attr_type(t_arrow(t_unit(), t_prim(.I32))))
        r := new_region(fn, .Fn_Body)
        op_add_region(fn, r)
        b := new_block("entry", r)
        region_add_block(r, b)

        // create a stray value NOT attached to any op in this block
        stray := new_value(t_prim(.I32), "undef")
        stray.def_kind = .From_Op
        // def_op nil → use-before-def + dangling

        // op that uses the stray
        use := new_op(OP_RETURN)
        op_add_operand(use, stray)
        block_append_op(b, use)

        module_append_op(m, fn)
        res := ir_verify(m)
        defer ir_verify_result_destroy(&res)
        if has_code(&res, .Ir_Use_Before_Def) || has_code(&res, .Ir_Dangling_Value) {
            fmt.println("CASE 2: PASS use-before-def/dangling")
            pass += 1
        } else {
            fmt.println("CASE 2: FAIL expected Ir_Use_Before_Def or Ir_Dangling_Value")
            dump_diags(&res)
        }
    }

    // ---- CASE 3 : type-mismatch on binop ----
    total += 1
    {
        ir_reset_ids()
        m := new_module("case3")
        fn := new_op(OP_FN)
        op_set_attr(fn, "name", attr_symbol("case3"))
        op_set_attr(fn, "sig",  attr_type(t_arrow(t_unit(), t_prim(.I32))))
        r := new_region(fn, .Fn_Body)
        op_add_region(fn, r)
        b := new_block("entry", r)
        region_add_block(r, b)

        // lhs : i32 const
        lhs := new_op(OP_CONST)
        op_set_attr(lhs, "value", attr_int(1))
        lv := op_add_result(lhs, t_prim(.I32))
        block_append_op(b, lhs)

        // rhs : bool const (intentionally mismatched)
        rhs := new_op(OP_CONST)
        op_set_attr(rhs, "value", attr_bool(true))
        rv := op_add_result(rhs, t_prim(.Bool))
        block_append_op(b, rhs)

        add := new_op(OP_ADD)
        op_add_operand(add, lv)
        op_add_operand(add, rv)
        sum := op_add_result(add, t_prim(.I32))
        block_append_op(b, add)

        term := new_op(OP_RETURN)
        op_add_operand(term, sum)
        block_append_op(b, term)

        module_append_op(m, fn)
        res := ir_verify(m)
        defer ir_verify_result_destroy(&res)
        if has_code(&res, .Ir_Type_Mismatch) {
            fmt.println("CASE 3: PASS type-mismatch")
            pass += 1
        } else {
            fmt.println("CASE 3: FAIL expected Ir_Type_Mismatch")
            dump_diags(&res)
        }
    }

    // ---- CASE 4 : region-shape (fn with 2 regions, cslv3.if with 1 region) ----
    total += 1
    {
        ir_reset_ids()
        m := new_module("case4")
        fn := new_op(OP_FN)
        op_set_attr(fn, "name", attr_symbol("case4"))
        op_set_attr(fn, "sig",  attr_type(t_arrow(t_unit(), t_prim(.Bool))))
        // deliberately add 2 regions to a fn — expected : exactly 1
        r1 := new_region(fn, .Fn_Body)
        r2 := new_region(fn, .Fn_Body)
        op_add_region(fn, r1)
        op_add_region(fn, r2)
        b1 := new_block("entry", r1)
        region_add_block(r1, b1)
        b2 := new_block("extra", r2)
        region_add_block(r2, b2)
        // each block needs a terminator or we'll also trigger missing-term
        ret1 := new_op(OP_RETURN)
        block_append_op(b1, ret1)
        ret2 := new_op(OP_RETURN)
        block_append_op(b2, ret2)

        module_append_op(m, fn)
        res := ir_verify(m)
        defer ir_verify_result_destroy(&res)
        if has_code(&res, .Ir_Region_Shape) {
            fmt.println("CASE 4: PASS region-shape")
            pass += 1
        } else {
            fmt.println("CASE 4: FAIL expected Ir_Region_Shape")
            dump_diags(&res)
        }
    }

    // ---- CASE 5 : terminator-kind (return inside If_Then is tolerated per rules ;
    //                                 instead, put cslv3.branch inside If_Then which IS wrong) ----
    total += 1
    {
        ir_reset_ids()
        m := new_module("case5")
        fn := new_op(OP_FN)
        op_set_attr(fn, "name", attr_symbol("case5"))
        op_set_attr(fn, "sig",  attr_type(t_arrow(t_unit(), t_prim(.Bool))))
        rf := new_region(fn, .Fn_Body)
        op_add_region(fn, rf)
        be := new_block("entry", rf)
        region_add_block(rf, be)

        // cslv3.if with 2 regions (correct shape) but each block terminated with
        // cslv3.branch — which is not valid for If_Then/If_Else (only yield/break/continue/return).
        ifop := new_op(OP_IF)
        cond_const := new_op(OP_CONST)
        op_set_attr(cond_const, "value", attr_bool(true))
        cv := op_add_result(cond_const, t_prim(.Bool))
        block_append_op(be, cond_const)
        op_add_operand(ifop, cv)

        rthen := new_region(ifop, .If_Then)
        relse := new_region(ifop, .If_Else)
        op_add_region(ifop, rthen)
        op_add_region(ifop, relse)
        bt := new_block("then", rthen)
        region_add_block(rthen, bt)
        bf := new_block("else", relse)
        region_add_block(relse, bf)
        br1 := new_op("cslv3.branch")
        block_append_op(bt, br1)
        br2 := new_op("cslv3.branch")
        block_append_op(bf, br2)
        block_append_op(be, ifop)

        term := new_op(OP_RETURN)
        block_append_op(be, term)
        module_append_op(m, fn)

        res := ir_verify(m)
        defer ir_verify_result_destroy(&res)
        if has_code(&res, .Ir_Terminator_Kind) {
            fmt.println("CASE 5: PASS terminator-kind")
            pass += 1
        } else {
            fmt.println("CASE 5: FAIL expected Ir_Terminator_Kind")
            dump_diags(&res)
        }
    }

    fmt.printf("IR-SELFTEST: %d/%d PASS\n", pass, total)
}

@(private="file")
has_code :: proc(r: ^Ir_Verify_Result, code: Sem_Code) -> bool {
    for d in r.diagnostics {
        if d.code == code do return true
    }
    return false
}

@(private="file")
dump_diags :: proc(r: ^Ir_Verify_Result) {
    for d in r.diagnostics {
        fmt.eprintf("  [%s] %s %s\n",
            severity_label(d.severity), sem_code_name(d.code), d.msg)
    }
}
