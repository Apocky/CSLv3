package cslparser

// § CSLv3 SMT SELF-TEST (T26 Session-7)
// I> programmatic tests of Formula + emit + morpheme-predicate + cache-hash
// I> ALWAYS-runnable without any external solver
// I> invocation : parser --smt-selftest
// I> emits CASE N: PASS/FAIL per check ; footer SMT-SELFTEST: k/n PASS
// R! ← pattern matches ir_selftest.odin

import "core:fmt"
import "core:strings"

smt_selftest_main :: proc(args: []string) {
    total := 0
    pass  := 0

    // ---- CASE 1 : boolean-tautology emission ----
    total += 1
    {
        s := new_script(.QF_UF)
        defer script_destroy(s)
        x := f_var("x", s_bool())
        script_declare_const(s, "x", s_bool())
        script_assert(s, f_or(x, f_not(x)))   // x ∨ ¬x
        s.logic = infer_theory(s)
        txt := emit_script(s)
        if strings.contains(txt, "(assert (or x (not x)))") &&
           strings.contains(txt, "(declare-const x Bool)") &&
           strings.contains(txt, "(check-sat)") {
            fmt.println("CASE 1: PASS bool-taut-emit")
            pass += 1
        } else {
            fmt.println("CASE 1: FAIL")
            fmt.eprintln(txt)
        }
    }

    // ---- CASE 2 : integer LIA emission ----
    total += 1
    {
        s := new_script(.QF_LIA)
        defer script_destroy(s)
        a := f_var("a", s_int())
        b := f_var("b", s_int())
        script_declare_const(s, "a", s_int())
        script_declare_const(s, "b", s_int())
        script_assert(s, f_gt(f_add(a, b), f_int(0)))
        s.logic = infer_theory(s)
        txt := emit_script(s)
        if strings.contains(txt, "(declare-const a Int)") &&
           strings.contains(txt, "(declare-const b Int)") &&
           strings.contains(txt, "(assert (> (+ a b) 0))") {
            fmt.println("CASE 2: PASS lia-emit")
            pass += 1
        } else {
            fmt.println("CASE 2: FAIL")
            fmt.eprintln(txt)
        }
    }

    // ---- CASE 3 : morpheme predicate (durative) ----
    total += 1
    {
        v := f_var("v", s_sym("MorphVal"))
        p := morpheme_predicate("d", v)
        txt := formula_repr(p)
        if strings.contains(txt, "(> (duration v) 0)") {
            fmt.println("CASE 3: PASS morpheme-d")
            pass += 1
        } else {
            fmt.println("CASE 3: FAIL morpheme-d")
            fmt.eprintln("got:", txt)
        }
    }

    // ---- CASE 4 : morpheme predicate (reflexive) ----
    total += 1
    {
        v := f_var("v", s_sym("MorphVal"))
        p := morpheme_predicate("r", v)
        txt := formula_repr(p)
        if strings.contains(txt, "(= (subject v) (object v))") {
            fmt.println("CASE 4: PASS morpheme-r")
            pass += 1
        } else {
            fmt.println("CASE 4: FAIL morpheme-r")
            fmt.eprintln("got:", txt)
        }
    }

    // ---- CASE 5 : morpheme stack composition ----
    total += 1
    {
        v := f_var("v", s_sym("MorphVal"))
        p := morpheme_stack_predicate([]string{"d", "f"}, v)
        txt := formula_repr(p)
        if strings.contains(txt, "(and") &&
           strings.contains(txt, "(> (duration v) 0)") &&
           strings.contains(txt, "(terminal v)") {
            fmt.println("CASE 5: PASS morpheme-stack")
            pass += 1
        } else {
            fmt.println("CASE 5: FAIL morpheme-stack")
            fmt.eprintln("got:", txt)
        }
    }

    // ---- CASE 6 : quantifier emission ----
    total += 1
    {
        s := new_script(.AUFLIA)
        defer script_destroy(s)
        binds := make([dynamic]Binding)
        defer delete(binds)
        append(&binds, Binding{name = "n", sort = s_int()})
        n := f_var("n", s_int())
        body := f_ge(f_add(n, n), f_int(0))
        script_assert(s, f_forall(binds, body))
        txt := emit_script(s)
        if strings.contains(txt, "(forall ((n Int))") &&
           strings.contains(txt, "(>= (+ n n) 0)") {
            fmt.println("CASE 6: PASS quant-emit")
            pass += 1
        } else {
            fmt.println("CASE 6: FAIL quant-emit")
            fmt.eprintln(txt)
        }
    }

    // ---- CASE 7 : canonical-emit determinism (hash-stability) ----
    total += 1
    {
        s := new_script(.QF_LIA)
        defer script_destroy(s)
        script_declare_const(s, "b", s_int())
        script_declare_const(s, "a", s_int())
        // declared in b-then-a order ; emit must sort alphabetically
        a := f_var("a", s_int())
        b := f_var("b", s_int())
        script_assert(s, f_lt(a, b))
        txt := emit_script(s)

        // Second script : same content, different insertion order
        s2 := new_script(.QF_LIA)
        defer script_destroy(s2)
        script_declare_const(s2, "a", s_int())
        script_declare_const(s2, "b", s_int())
        script_assert(s2, f_lt(a, b))
        txt2 := emit_script(s2)

        hash1 := sha256_hex_of_string(txt)
        hash2 := sha256_hex_of_string(txt2)
        if hash1 == hash2 {
            fmt.println("CASE 7: PASS canonical-determinism")
            pass += 1
        } else {
            fmt.println("CASE 7: FAIL canonical-determinism (hashes differ)")
            fmt.eprintf("  h1=%s\n  h2=%s\n", hash1, hash2)
        }
    }

    // ---- CASE 8 : SHA256 vector ----
    total += 1
    {
        // empty-string SHA256 = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
        got := sha256_hex_of_string("")
        want := "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        if got == want {
            fmt.println("CASE 8: PASS sha256-vector")
            pass += 1
        } else {
            fmt.println("CASE 8: FAIL sha256-vector")
            fmt.eprintf("  got =%s\n  want=%s\n", got, want)
        }
    }

    // ---- CASE 9 : theory auto-inference ----
    total += 1
    {
        s := new_script(.ALL)
        defer script_destroy(s)
        script_declare_const(s, "x", s_int())
        script_declare_const(s, "y", s_int())
        x := f_var("x", s_int())
        y := f_var("y", s_int())
        script_assert(s, f_gt(f_add(x, y), f_int(0)))
        got := infer_theory(s)
        if got == .QF_LIA {
            fmt.println("CASE 9: PASS theory-lia")
            pass += 1
        } else {
            fmt.println("CASE 9: FAIL")
            fmt.eprintf("  got=%v want=QF_LIA\n", got)
        }
    }

    // ---- CASE 10 : non-linear auto-detection ----
    total += 1
    {
        s := new_script(.ALL)
        defer script_destroy(s)
        script_declare_const(s, "x", s_int())
        script_declare_const(s, "y", s_int())
        x := f_var("x", s_int())
        y := f_var("y", s_int())
        script_assert(s, f_eq(f_mul(x, y), f_int(1)))   // x*y : non-linear
        got := infer_theory(s)
        if got == .QF_NIA {
            fmt.println("CASE 10: PASS theory-nia")
            pass += 1
        } else {
            fmt.println("CASE 10: FAIL")
            fmt.eprintf("  got=%v want=QF_NIA\n", got)
        }
    }

    // ---- Optional CASE 11 : end-to-end discharge if solver available ----
    if len(args) > 0 {
        total += 1
        z3_path := ""
        for a in args {
            if strings.has_prefix(a, "--z3=") {
                z3_path = a[len("--z3="):]
            }
        }
        if z3_path != "" {
            s := new_script(.QF_LIA)
            defer script_destroy(s)
            script_declare_const(s, "x", s_int())
            x := f_var("x", s_int())
            // assert x = 5 ∧ x < 0  ⇒ unsat
            script_assert(s, f_eq(x, f_int(5)))
            script_assert(s, f_lt(x, f_int(0)))
            txt := emit_script(s)
            result, ok := solve_with("z3", txt, 10_000, z3_path)
            if ok && result == .Unsat {
                fmt.println("CASE 11: PASS z3-unsat-roundtrip")
                pass += 1
            } else {
                fmt.println("CASE 11: FAIL z3-unsat-roundtrip")
                fmt.eprintf("  ok=%t result=%v\n", ok, result)
            }
        } else {
            fmt.println("CASE 11: SKIP (no --z3=<path> provided)")
            // don't count toward total when skipped
            total -= 1
        }
    }

    fmt.printf("SMT-SELFTEST: %d/%d PASS\n", pass, total)
}
