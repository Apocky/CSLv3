package cslparser

// § CSLv3 PARSER — CLI ENTRY POINT
// I> reads .csl file → lexer → parser → optional semantic/print/roundtrip
// I> T14 (Session-4) : severity-mode flags wired end-to-end
//
// usage : cslparser [MODE-FLAGS] [SEVERITY-FLAGS] [PRINT-FLAGS] <file>
//
// mode flags :
//   --tokens | --lex    dump token stream
//   --errors            parse + print diagnostics only
//   --semantic          parse + semantic pass + summary
//   --print             pretty-print source
//   --roundtrip         parse → print → reparse → AST-shape-equal check
//   (default)           parse + pretty-print AST (S-expression)
//
// severity flags (affect --semantic + default exit-code) :
//   --lint              warn-only ; exit 0 ; editor-surface
//   (none)              default   ; E → exit 1
//   --strict            any W or E → exit 1 (CI-gate)
//   --strict-parse      PERMISSIVE_ACCEPT → E (orthogonal ; combines with --strict)
//   --verbose | -v      surface Info diagnostics (compound-assoc etc.)
//
// print flags (affect --print + --roundtrip rendering) :
//   --mode=canonical|compact|literate|ascii-only|unicode-only

import "core:fmt"
import "core:os"
import "core:strings"

Mode :: enum { Parse, Tokens, Errors, Semantic, Print, Roundtrip, Cssllint, Typecheck, Ir, Smt, Emit }

main :: proc() {
    args := os.args
    if len(args) < 2 {
        print_usage()
        os.exit(2)
    }
    // Subcommand form : `parser cssllint [flags] <file>`
    // (positional first arg dispatches before flag-parse for T19 CSSLv3 bridge)
    if len(args) >= 2 && args[1] == "cssllint" {
        cssllint_main(args[2:])
        return
    }
    // T21 : `--ir-selftest` runs programmatic IR-verifier tests (no file required).
    if len(args) >= 2 && args[1] == "--ir-selftest" {
        ir_selftest_main()
        return
    }
    // T26 : `--smt-selftest` runs programmatic SMT-formula + emit tests (no file required).
    if len(args) >= 2 && args[1] == "--smt-selftest" {
        smt_selftest_main(args[2:])
        return
    }
    // T28 : `--emit-selftest` runs 5 emit-targets against a canonical sample
    if len(args) >= 2 && args[1] == "--emit-selftest" {
        emit_selftest_main()
        return
    }
    // Session-13 P2.1 : `--distance <a> <b>` prints Levenshtein distance.
    if len(args) >= 4 && args[1] == "--distance" {
        d := levenshtein(args[2], args[3])
        fmt.printf("%d\n", d)
        os.exit(0)
    }
    // Session-13 P2.2 : `--sha256 <file>` prints SHA-256 hex digest.
    if len(args) >= 3 && args[1] == "--sha256" {
        ok, hex := sha256_file(args[2])
        if !ok {
            fmt.eprintf("sha256: cannot read %s\n", args[2])
            os.exit(1)
        }
        fmt.printf("%s  %s\n", hex, args[2])
        os.exit(0)
    }
    // Session-13 P2.2 : `--sha256-selftest` runs NIST test-vectors.
    if len(args) >= 2 && args[1] == "--sha256-selftest" {
        sha256_selftest()
        return
    }
    // Session-13 P2.3 : `--ed25519-selftest` runs RFC-8032 test-vectors.
    if len(args) >= 2 && args[1] == "--ed25519-selftest" {
        ed25519_selftest()
        return
    }
    // Session-14 A4 : `--json-selftest` runs RFC 8259 round-trip + reject cases.
    if len(args) >= 2 && args[1] == "--json-selftest" {
        json_selftest()
        return
    }
    // Session-14 A2 : `--blake3-selftest` runs reference test vectors.
    if len(args) >= 2 && args[1] == "--blake3-selftest" {
        blake3_selftest()
        return
    }
    // Session-14 A7 : `--uri-selftest` runs RFC 3986 vectors.
    if len(args) >= 2 && args[1] == "--uri-selftest" {
        uri_selftest()
        return
    }
    // Session-14 A7 : `--uri-parse <uri>` prints component breakdown.
    if len(args) >= 3 && args[1] == "--uri-parse" {
        u, _ := uri_parse(args[2])
        fmt.printf("scheme   : %s\n", u.scheme)
        fmt.printf("userinfo : %s\n", u.userinfo)
        fmt.printf("host     : %s\n", u.host)
        fmt.printf("port     : %s\n", u.port)
        fmt.printf("path     : %s\n", u.path)
        fmt.printf("query    : %s\n", u.query)
        fmt.printf("fragment : %s\n", u.fragment)
        os.exit(0)
    }
    // Session-14 A2 : `--blake3 <file>` prints BLAKE3 hex.
    if len(args) >= 3 && args[1] == "--blake3" {
        data, err := os.read_entire_file_from_path(args[2], context.allocator)
        if err != nil {
            fmt.eprintf("blake3: cannot read %s\n", args[2])
            os.exit(1)
        }
        fmt.printf("%s  %s\n", blake3_hex(data), args[2])
        delete(data)
        os.exit(0)
    }
    // Session-14 A4 : `--json-validate <file>` exits 0 if valid, 1 if not.
    if len(args) >= 3 && args[1] == "--json-validate" {
        data, read_err := os.read_entire_file_from_path(args[2], context.allocator)
        if read_err != nil {
            fmt.eprintf("json-validate: cannot read %s\n", args[2])
            os.exit(2)
        }
        v, e := json_parse(string(data))
        delete(data)
        if !e.ok {
            fmt.printf("FAIL %s @ L%d C%d : %s\n", args[2], e.line, e.col, e.msg)
            os.exit(1)
        }
        json_free(v)
        fmt.printf("OK %s\n", args[2])
        os.exit(0)
    }
    // Session-13 P2.3 : `--sign <file> --key=<priv>` emits hex signature.
    if len(args) >= 3 && args[1] == "--sign" {
        key_path := ""
        for a in args[2:] {
            if len(a) > 6 && a[:6] == "--key=" do key_path = a[6:]
        }
        // positional file is first non-flag arg after --sign
        file_path := ""
        for a in args[2:] {
            if len(a) > 0 && a[0] != '-' { file_path = a; break }
        }
        if file_path == "" || key_path == "" {
            fmt.eprintln("usage: parser --sign <file> --key=<priv32.bin>")
            os.exit(2)
        }
        sig, ok := ed25519_sign_file(file_path, key_path)
        if !ok {
            fmt.eprintf("sign: failed for %s (key=%s)\n", file_path, key_path)
            os.exit(1)
        }
        fmt.println(sig)
        os.exit(0)
    }
    // Session-13 P2.3 : `--verify <file> --sig=<hex-or-bin> --key=<pub>`.
    if len(args) >= 4 && args[1] == "--verify" {
        sig_path := ""
        key_path := ""
        file_path := ""
        for a in args[2:] {
            if len(a) > 6 && a[:6] == "--sig=" do sig_path = a[6:]
            else if len(a) > 6 && a[:6] == "--key=" do key_path = a[6:]
            else if len(a) > 0 && a[0] != '-' && file_path == "" do file_path = a
        }
        if file_path == "" || sig_path == "" || key_path == "" {
            fmt.eprintln("usage: parser --verify <file> --sig=<64.bin> --key=<pub32.bin>")
            os.exit(2)
        }
        ok := ed25519_verify_file(file_path, sig_path, key_path)
        if ok {
            fmt.println("OK")
            os.exit(0)
        } else {
            fmt.println("FAIL")
            os.exit(1)
        }
    }
    // T26.1 : `--smt-audit-verify [dir]` walks chain.jsonl + verifies sigs
    if len(args) >= 2 && args[1] == "--smt-audit-verify" {
        dir := ".proof"
        if len(args) >= 3 do dir = args[2]
        ok, n := ir_verify_audit_chain(dir)
        fmt.printf("audit-chain %s: verified=%d %s\n",
            dir, n, "OK" if ok else "FAIL")
        os.exit(0 if ok else 1)
    }
    mode    := Mode.Parse
    pmode   := Print_Mode.Canonical
    sev     := Sem_Mode.Default
    strict_parse := false
    verbose := false
    want_json := false
    want_verify := false
    want_no_cache := false
    want_dump_lib2 := false
    smt_timeout_ms := 10_000
    smt_z3_path   := find_solver_default("z3")
    smt_cvc5_path := find_solver_default("cvc5")
    smt_prefer    := ""
    opt_level     := -1   // -1 = unset ; >=0 selected via --opt=ON
    custom_passes := ""
    want_stats    := false
    want_verify_each := false
    emit_target   := Emit_Target.JSON
    emit_target_set := false
    emit_sign     := false
    emit_incremental := false
    emit_no_sourcemap := false
    emit_standalone := true
    emit_schema_print := false
    emit_out_path := ""
    file_path := ""

    for i in 1 ..< len(args) {
        a := args[i]
        switch a {
        case "--tokens", "--lex":            mode = .Tokens
        case "--errors":                     mode = .Errors
        case "--semantic":                   mode = .Semantic
        case "--print":                      mode = .Print
        case "--roundtrip":                  mode = .Roundtrip
        case "--typecheck":                  mode = .Typecheck
        case "--ir":                         mode = .Ir
        case "--smt":                        mode = .Smt
        case "--verify":                     want_verify = true
        case "--no-cache":                   want_no_cache = true
        case "--dump-lib2":                  want_dump_lib2 = true
        case "--json":                       want_json = true

        case "--solver=z3":                  smt_prefer = "z3"
        case "--solver=cvc5":                smt_prefer = "cvc5"

        case "--opt=O0", "--opt=0":          opt_level = 0
        case "--opt=O1", "--opt=1":          opt_level = 1
        case "--opt=O2", "--opt=2":          opt_level = 2
        case "--opt=O3", "--opt=3":          opt_level = 3
        case "--stats":                      want_stats = true
        case "--verify-each":                want_verify_each = true

        case "--sign":                       emit_sign = true
        case "--incremental":                emit_incremental = true
        case "--no-source-map":              emit_no_sourcemap = true
        case "--fragment":                   emit_standalone = false
        case "--schema":                     emit_schema_print = true

        case "--lint":                       sev = .Lint
        case "--strict":                     sev = .Strict
        case "--strict-parse":               strict_parse = true
        case "--verbose", "-v":              verbose = true

        case "--mode=canonical":             pmode = .Canonical
        case "--mode=compact":               pmode = .Compact
        case "--mode=literate":              pmode = .Literate
        case "--mode=ascii-only":            pmode = .AsciiOnly
        case "--mode=unicode-only":          pmode = .UnicodeOnly

        case "--help", "-h":
            print_usage()
            os.exit(0)
        case:
            if strings.has_prefix(a, "--emit=") {
                name := a[len("--emit="):]
                if t, ok := emit_target_parse(name); ok {
                    emit_target = t
                    emit_target_set = true
                    mode = .Emit
                } else {
                    fmt.eprintf("unknown --emit target: %s\n", name)
                    os.exit(2)
                }
            } else if strings.has_prefix(a, "--out=") {
                emit_out_path = a[len("--out="):]
            } else if strings.has_prefix(a, "--z3=") {
                smt_z3_path = a[len("--z3="):]
            } else if strings.has_prefix(a, "--cvc5=") {
                smt_cvc5_path = a[len("--cvc5="):]
            } else if strings.has_prefix(a, "--timeout=") {
                smt_timeout_ms = parse_timeout(a[len("--timeout="):])
            } else if strings.has_prefix(a, "--opt=custom") {
                opt_level = -2
            } else if strings.has_prefix(a, "--passes=") {
                custom_passes = a[len("--passes="):]
                if opt_level < 0 do opt_level = -2
            } else if strings.has_prefix(a, "--") {
                fmt.eprintf("unknown option: %s\n", a)
                os.exit(2)
            } else {
                file_path = a
            }
        }
    }
    if len(file_path) == 0 {
        print_usage()
        os.exit(2)
    }
    src_bytes, rerr := os.read_entire_file_from_path(file_path, context.allocator)
    if rerr != nil {
        fmt.eprintf("error: cannot read '%s': %v\n", file_path, rerr)
        os.exit(1)
    }
    src := string(src_bytes)
    defer delete(src_bytes, context.allocator)

    #partial switch mode {
    case .Tokens:
        dump_tokens(src, file_path)

    case .Errors:
        doc, lex_errs, parse_errs := parse_source(src, file_path)
        _ = doc
        report_errors(lex_errs, parse_errs)
        if len(lex_errs) > 0 || len(parse_errs) > 0 do os.exit(1)

    case .Parse:
        doc, lex_errs, parse_errs := parse_source(src, file_path)
        report_errors(lex_errs, parse_errs)
        sb := strings.builder_make()
        ast_sprint(doc, 0, &sb)
        fmt.print(strings.to_string(sb))
        if len(lex_errs) > 0 || len(parse_errs) > 0 do os.exit(1)

    case .Semantic:
        doc, lex_errs, parse_errs := parse_source(src, file_path)
        report_errors(lex_errs, parse_errs)
        res := semantic_analyze_with_mode(doc, sev, strict_parse)
        defer semantic_result_destroy(&res)
        fmt.print(semantic_render_summary(&res, verbose))
        sb := strings.builder_make()
        ast_sprint(doc, 0, &sb)
        fmt.print(strings.to_string(sb))
        if len(lex_errs) > 0 || len(parse_errs) > 0 do os.exit(1)
        if semantic_fails(&res) do os.exit(1)

    case .Print:
        doc, lex_errs, parse_errs := parse_source(src, file_path)
        report_errors(lex_errs, parse_errs)
        res := semantic_analyze_with_mode(doc, sev, strict_parse)
        defer semantic_result_destroy(&res)
        sb := strings.builder_make()
        pprint_doc_with_mode(doc, &sb, pmode)
        fmt.print(strings.to_string(sb))
        if len(lex_errs) > 0 || len(parse_errs) > 0 do os.exit(1)
        if semantic_fails(&res) do os.exit(1)

    case .Roundtrip:
        ok, reason := round_trip_ok(src, file_path)
        if ok {
            fmt.printf("ROUND-TRIP OK: %s\n", file_path)
        } else {
            fmt.eprintf("ROUND-TRIP FAIL: %s -- %s\n", file_path, reason)
            os.exit(1)
        }

    case .Typecheck:
        typecheck_cli(src, file_path, sev, strict_parse, verbose, want_json)

    case .Ir:
        ir_cli(src, file_path, sev, strict_parse, verbose, want_json, want_verify,
               opt_level, custom_passes, want_stats, want_verify_each,
               smt_z3_path, smt_cvc5_path)

    case .Smt:
        smt_cli(src, file_path, sev, strict_parse, verbose, want_json,
                want_no_cache, want_dump_lib2, smt_timeout_ms,
                smt_z3_path, smt_cvc5_path, smt_prefer)

    case .Emit:
        _ = emit_target_set
        emit_cli(src, file_path, sev, strict_parse, emit_target,
                 emit_out_path, emit_sign, emit_incremental,
                 !emit_no_sourcemap, emit_standalone, emit_schema_print)
    }
}

parse_timeout :: proc(s: string) -> int {
    if len(s) == 0 do return 10_000
    n := 0
    i := 0
    for i < len(s) && s[i] >= '0' && s[i] <= '9' {
        n = n * 10 + int(s[i] - '0')
        i += 1
    }
    if i < len(s) {
        suffix := s[i:]
        switch suffix {
        case "s", "sec", "seconds": return n * 1000
        case "ms", "millis":        return n
        case "m", "min":            return n * 60_000
        }
    }
    return n   // default : ms
}

find_solver_default :: proc(name: string) -> string {
    env_key: string
    switch name {
    case "z3":   env_key = "Z3_PATH"
    case "cvc5": env_key = "CVC5_PATH"
    case:        return ""
    }
    env_val := os.get_env(env_key, context.allocator)
    if len(env_val) > 0 && os.exists(env_val) do return env_val
    // common fallback paths
    candidates: []string
    switch name {
    case "z3":
        candidates = []string{
            "C:/ProgramData/chocolatey/bin/z3.exe",
            "C:/Program Files/Z3/bin/z3.exe",
            "z3.exe",
            "z3",
        }
    case "cvc5":
        candidates = []string{
            "C:/Program Files/cvc5/bin/cvc5.exe",
            "cvc5.exe",
            "cvc5",
        }
    }
    for c in candidates do if os.exists(c) do return c
    return ""
}

typecheck_cli :: proc(src: string, file_path: string, sev: Sem_Mode, strict_parse: bool, verbose: bool, want_json: bool) {
    doc, lex_errs, parse_errs := parse_source(src, file_path)
    // structural errors are always fatal for type-check
    if len(lex_errs) > 0 || len(parse_errs) > 0 {
        report_errors(lex_errs, parse_errs)
        if !want_json do os.exit(1)
    }
    r := typecheck(doc, sev, strict_parse)
    defer tc_result_destroy(&r)

    if want_json {
        info, warn, err := 0, 0, 0
        for d in r.diagnostics {
            #partial switch d.severity {
            case .Info:  info += 1
            case .Warn:  warn += 1
            case .Error: err  += 1
            }
        }
        err += len(lex_errs) + len(parse_errs)
        fmt.printf(`{{"file":"%s","status":"`, json_escape(file_path))
        if err > 0      do fmt.print("error")
        else if warn > 0 do fmt.print("warn")
        else             do fmt.print("ok")
        fmt.printf(`","counts":{{"info":%d,"warn":%d,"error":%d}},"diags":[`,
            info, warn, err)
        first := true
        for &e in lex_errs {
            if !first do fmt.print(",")
            first = false
            fmt.printf(`{{"line":%d,"col":%d,"sev":"error","code":"CSL-E-LEX","msg":"%s"}}`,
                e.pos.line, e.pos.col, json_escape(e.msg))
        }
        for &e in parse_errs {
            if !first do fmt.print(",")
            first = false
            fmt.printf(`{{"line":%d,"col":%d,"sev":"error","code":"CSL-E-PARSE","msg":"%s"}}`,
                e.pos.line, e.pos.col, json_escape(e.msg))
        }
        for d in r.diagnostics {
            if d.severity == .Info && !verbose do continue
            if !first do fmt.print(",")
            first = false
            fmt.printf(`{{"line":%d,"col":%d,"sev":"%s","code":"%s","msg":"%s"}}`,
                d.pos.line, d.pos.col,
                severity_label(d.severity),
                tc_code_for(d.code),
                json_escape(d.msg))
        }
        fmt.print("]}\n")
    } else {
        fmt.print(tc_render_summary(&r, verbose))
    }
    if tc_fails(&r) do os.exit(1)
}

// T21 (Session-6) IR CLI.
// usage : parser --ir [--json] [--verify] [--strict] <file>
//   default          → print MLIR-flavor textual IR dump
//   --json           → print JSON IR dump (sorted-keys, deterministic)
//   --verify         → run ir_verify + emit diagnostics
//   --strict         → any E or W → exit 1 (CI-gate ; composes with --verify)
ir_cli :: proc(src: string, file_path: string, sev: Sem_Mode,
               strict_parse: bool, verbose: bool,
               want_json: bool, want_verify: bool,
               opt_level: int, custom_passes: string,
               want_stats: bool, want_verify_each: bool,
               z3_path, cvc5_path: string) {
    doc, lex_errs, parse_errs := parse_source(src, file_path)
    if len(lex_errs) > 0 || len(parse_errs) > 0 {
        report_errors(lex_errs, parse_errs)
        if !want_json do os.exit(1)
    }
    tc_res := typecheck(doc, sev, strict_parse)
    defer tc_result_destroy(&tc_res)

    lowered := lower_source(doc, &tc_res, file_path)

    // T27 : if opt-level requested, run the pass pipeline on the lowered module.
    pass_stats_text := ""
    pass_stats_json := ""
    if opt_level >= 0 || opt_level == -2 {
        pc: Pass_Ctx
        lvl := opt_level
        if lvl < 0 do lvl = 2   // custom → default fuel at O2
        pass_ctx_init(&pc, lvl)
        defer pass_ctx_destroy(&pc)
        pc.tc          = &tc_res
        pc.z3_path     = z3_path
        pc.cvc5_path   = cvc5_path
        pc.verify_each = want_verify_each

        pm: Pass_Manager
        pm_init(&pm, &pc)
        defer pm_destroy(&pm)
        if opt_level == -2 {
            build_custom_pipeline(&pm, custom_passes)
        } else {
            build_default_pipeline(&pm, opt_level)
        }
        pm_run(&pm, lowered.module)
        if want_stats {
            pass_stats_text = stats_report_text(&pc, pm.total_ms)
            pass_stats_json = stats_report_json(&pc, pm.total_ms)
        }
    }

    // count lowering + verifier diagnostics
    low_errs, low_warns := 0, 0
    for d in lowered.diagnostics {
        #partial switch d.severity {
        case .Error: low_errs  += 1
        case .Warn:  low_warns += 1
        }
    }

    ver_res: Ir_Verify_Result
    if want_verify {
        ver_res = ir_verify(lowered.module)
    }

    if want_json {
        fmt.printf(`{{"file":"%s","status":"`, json_escape(file_path))
        total_err := low_errs + (ver_res.errors if want_verify else 0)
        total_warn := low_warns + (ver_res.warnings if want_verify else 0)
        if total_err > 0      do fmt.print("error")
        else if total_warn > 0 do fmt.print("warn")
        else                   do fmt.print("ok")
        fmt.printf(`","counts":{{"lower_err":%d,"lower_warn":%d,"verify_err":%d,"verify_warn":%d}},`,
            low_errs, low_warns,
            ver_res.errors   if want_verify else 0,
            ver_res.warnings if want_verify else 0)
        fmt.print(`"ir":`)
        fmt.print(ir_json_module(lowered.module))
        fmt.print(",\"diags\":[")
        first := true
        for d in lowered.diagnostics {
            if d.severity == .Info && !verbose do continue
            if !first do fmt.print(",")
            first = false
            fmt.printf(`{{"line":%d,"col":%d,"sev":"%s","code":"%s","phase":"lower","msg":"%s"}}`,
                d.pos.line, d.pos.col,
                severity_label(d.severity),
                sem_code_name(d.code),
                json_escape(d.msg))
        }
        if want_verify {
            for d in ver_res.diagnostics {
                if d.severity == .Info && !verbose do continue
                if !first do fmt.print(",")
                first = false
                fmt.printf(`{{"line":%d,"col":%d,"sev":"%s","code":"%s","phase":"verify","msg":"%s"}}`,
                    d.pos.line, d.pos.col,
                    severity_label(d.severity),
                    sem_code_name(d.code),
                    json_escape(d.msg))
            }
        }
        fmt.print("]")
        if pass_stats_json != "" {
            fmt.print(",\"pass_stats\":")
            fmt.print(pass_stats_json)
        }
        fmt.print("}\n")
    } else {
        // textual IR dump
        fmt.print(ir_print_module(lowered.module))
        if pass_stats_text != "" {
            fmt.print(pass_stats_text)
        }
        for d in lowered.diagnostics {
            if d.severity == .Info && !verbose do continue
            fmt.eprintf("%s:%d:%d: %s [%s] %s\n",
                file_path, d.pos.line, d.pos.col,
                severity_label(d.severity), sem_code_name(d.code), d.msg)
        }
        if want_verify {
            for d in ver_res.diagnostics {
                if d.severity == .Info && !verbose do continue
                fmt.eprintf("%s:%d:%d: %s [%s] %s\n",
                    file_path, d.pos.line, d.pos.col,
                    severity_label(d.severity), sem_code_name(d.code), d.msg)
            }
            fmt.eprintf("ir-verify: %d error(s), %d warning(s)\n", ver_res.errors, ver_res.warnings)
        }
    }

    // exit-code
    fail := false
    if low_errs > 0 do fail = true
    if want_verify && ver_res.errors > 0 do fail = true
    if sev == .Strict && (low_warns > 0 || (want_verify && ver_res.warnings > 0)) do fail = true
    if fail do os.exit(1)
}

// T26 (Session-7) SMT CLI.
// usage : parser --smt [--json] [--strict] [--no-cache] [--dump-lib2]
//                      [--solver=z3|cvc5]
//                      [--timeout=10s] [--z3=<path>] [--cvc5=<path>] <file>
//
// exit-code :
//   0  all obligations discharged (Unsat) OR no obligations collected
//   1  any Sat (counter-example) OR --strict + any Unknown/Timeout
//   2  solver invocation error ; or file-read error
smt_cli :: proc(src: string, file_path: string, sev: Sem_Mode,
                strict_parse: bool, verbose: bool,
                want_json: bool, no_cache: bool, dump_lib2: bool,
                timeout_ms: int, z3_path, cvc5_path, prefer: string) {
    doc, lex_errs, parse_errs := parse_source(src, file_path)
    if len(lex_errs) > 0 || len(parse_errs) > 0 {
        report_errors(lex_errs, parse_errs)
        if !want_json do os.exit(1)
    }
    tc_res := typecheck(doc, sev, strict_parse)
    defer tc_result_destroy(&tc_res)

    lowered := lower_source(doc, &tc_res, file_path)

    // Collect obligations from (a) typecheck refine-queue (b) IR walk.
    oblig := collect_from_refine_queue()
    defer delete(oblig)
    ir_obs := collect_from_ir(lowered.module)
    defer delete(ir_obs)
    for o in ir_obs do append(&oblig, o)

    // dump-lib2 : emit canonical SMT-LIB2 for each obligation and exit
    if dump_lib2 {
        for o, i in oblig {
            fmt.printf("; ============ obligation %d : %s\n", i, o.context_)
            fmt.print(canonical_emit(o.script))
            fmt.print("\n")
        }
        return
    }

    cfg := Discharge_Config{
        timeout_ms    = timeout_ms,
        use_cache     = !no_cache,
        cache_dir     = ".proof-cache",
        z3_path       = z3_path,
        cvc5_path     = cvc5_path,
        prefer_solver = prefer,
        strict        = sev == .Strict,
    }

    res := discharge(&oblig, cfg)

    // audit-chain : append each discharged obligation
    if !no_cache {
        _ = audit_init(".proof")
        for &o in oblig {
            if o.result == .Unsat || o.result == .Sat {
                _ = audit_append(".proof", &o)
            }
        }
    }

    if want_json {
        emit_smt_json(file_path, z3_path, cvc5_path, oblig, res, verbose)
    } else {
        emit_smt_text(file_path, z3_path, cvc5_path, oblig, res, verbose)
    }

    // exit-code : mode-classified
    fail := false
    if res.failure_count > 0 do fail = true
    if cfg.strict && res.inconclusive_count > 0 do fail = true
    if fail do os.exit(1)
}

emit_smt_text :: proc(file_path, z3_path, cvc5_path: string,
                       oblig: [dynamic]Obligation, res: Discharge_Result, verbose: bool) {
    fmt.printf("§ SMT-DISCHARGE %s\n", file_path)
    if z3_path != "" do fmt.printf("  z3  : %s\n", z3_path)
    else do fmt.println("  z3  : <not available — skip>")
    if cvc5_path != "" do fmt.printf("  cvc5: %s\n", cvc5_path)
    else do fmt.println("  cvc5: <not available — skip>")
    fmt.printf("  obligations: %d\n", len(oblig))
    fmt.printf("  ok=%d failure=%d inconclusive=%d  (raw: unsat=%d sat=%d unk=%d timeout=%d err=%d skip=%d)\n",
        res.ok_count, res.failure_count, res.inconclusive_count,
        res.unsat_count, res.sat_count, res.unknown_count,
        res.timeout_count, res.error_count, res.skipped_count)
    fmt.printf("  cache: %d hits / %d misses\n", res.cache_hits, res.cache_misses)
    fmt.printf("  total-ms: %d\n", res.total_ms)
    if verbose || res.failure_count > 0 || res.inconclusive_count > 0 {
        for &o in oblig {
            icon := "  "
            if obligation_is_success(&o) { icon = "✓ " }
            else if obligation_is_failure(&o) { icon = "✗ " }
            else {
                switch o.result {
                case .Unknown: icon = "? "
                case .Timeout: icon = "⊘ "
                case .Error:   icon = "! "
                case .Skipped: icon = "○ "
                case .Pending, .Unsat, .Sat:
                }
            }
            cached := " (cached)" if o.cached else ""
            mode_label := "Consist" if o.mode == .Consistency else "Verify "
            fmt.printf("  %s[%s/%s] %s — %s via %s%s\n",
                icon, mode_label, obligation_kind_name(o.kind),
                smt_result_name(o.result), o.context_, o.solver_used, cached)
        }
    }
}

emit_smt_json :: proc(file_path, z3_path, cvc5_path: string,
                       oblig: [dynamic]Obligation, res: Discharge_Result, verbose: bool) {
    fmt.printf(`{{"file":%q,"z3_path":%q,"cvc5_path":%q,`,
        file_path, z3_path, cvc5_path)
    fmt.printf(`"counts":{{"ok":%d,"failure":%d,"inconclusive":%d,"unsat":%d,"sat":%d,"unknown":%d,"timeout":%d,"error":%d,"skipped":%d}},`,
        res.ok_count, res.failure_count, res.inconclusive_count,
        res.unsat_count, res.sat_count, res.unknown_count,
        res.timeout_count, res.error_count, res.skipped_count)
    fmt.printf(`"cache":{{"hits":%d,"misses":%d}},"total_ms":%d,`,
        res.cache_hits, res.cache_misses, res.total_ms)
    status := "ok"
    if res.failure_count > 0 do status = "error"
    else if res.inconclusive_count > 0 do status = "warn"
    fmt.printf(`"status":%q,"obligations":[`, status)
    for &o, i in oblig {
        if i > 0 do fmt.print(",")
        mode_s := "consistency" if o.mode == .Consistency else "verification"
        ok_s := obligation_is_success(&o)
        fmt.printf(`{{"kind":%q,"mode":%q,"result":%q,"ok":%t,"solver":%q,"ctx":%q,"cert":%q,"cached":%t,"elapsed_ms":%d,"line":%d,"col":%d}}`,
            obligation_kind_name(o.kind),
            mode_s,
            smt_result_name(o.result),
            ok_s,
            o.solver_used,
            json_escape(o.context_),
            o.cert_hash,
            o.cached,
            o.elapsed_ms,
            o.source.line, o.source.col)
    }
    fmt.print("]}\n")
    _ = verbose
}

// T28 (Session-10) EMIT CLI.
// usage : parser --emit=<target> [--out=<path>] [--sign] [--incremental]
//                [--fragment] [--no-source-map] [--schema] <file>
//
// targets : mir | markdown | html | latex | json
// exit-code : 0 on success ; 1 on emit-failure or parse-error
emit_cli :: proc(src: string, file_path: string, sev: Sem_Mode, strict_parse: bool,
                 target: Emit_Target, out_path: string,
                 sign: bool, incremental: bool, source_map: bool,
                 standalone: bool, schema_print: bool) {
    if schema_print {
        fmt.print(schema_text_for(target))
        return
    }

    doc, lex_errs, parse_errs := parse_source(src, file_path)
    if len(lex_errs) > 0 || len(parse_errs) > 0 {
        report_errors(lex_errs, parse_errs)
    }

    tc_res := typecheck(doc, sev, strict_parse)
    defer tc_result_destroy(&tc_res)

    lowered := lower_source(doc, &tc_res, file_path)

    ctx: Emit_Context
    emit_context_init(&ctx, target)
    defer emit_context_destroy(&ctx)
    ctx.source_file = file_path
    ctx.source_text = src
    ctx.ast_root    = doc
    ctx.tc_result   = &tc_res
    ctx.ir_module   = lowered.module
    ctx.config.sign        = sign
    ctx.config.incremental = incremental
    ctx.config.source_map  = source_map
    ctx.config.standalone  = standalone
    ctx.config.out_path    = out_path

    r := emit(&ctx)

    if out_path == "" {
        fmt.print(r.bytes)
    } else {
        ok := os.write_entire_file(out_path, transmute([]byte)r.bytes)
        if ok != nil {
            fmt.eprintf("emit: failed to write %s: %v\n", out_path, ok)
            os.exit(1)
        }
        if source_map && r.source_map != "" {
            map_path := fmt.tprintf("%s.map", out_path)
            _ = os.write_entire_file(map_path, transmute([]byte)r.source_map)
        }
        if sign && r.cert != "" {
            cert_path := fmt.tprintf("%s.cert", out_path)
            _ = os.write_entire_file(cert_path, transmute([]byte)r.cert)
        }
        fmt.eprintf("emit: wrote %d bytes to %s (schema=%s cached=%t ms=%d)\n",
            len(r.bytes), out_path, r.schema_version, r.cached, r.elapsed_ms)
    }
    // Surface warnings to stderr
    for w in r.warnings {
        fmt.eprintf("emit: warn: %s\n", w)
    }
}

// T20 : map internal Sem_Code → stable CSL-E-2xx / CSL-W-2xx code strings
// so cssllint JSON emits a distinct namespace for type-checker diagnostics.
tc_code_for :: proc(c: Sem_Code) -> string {
    #partial switch c {
    case .Morph_Order:     return "CSL-E-200 type-mismatch"
    case .Morph_Unknown:   return "CSL-W-201 ambiguous-type"
    case .Slot_Arity:      return "CSL-W-204 unused-binding"
    case .Compound_Assoc:  return "CSL-I-205 shadow"
    }
    return sem_code_name(c)
}

print_usage :: proc() {
    fmt.eprintln("cslparser -- Caveman Spec Language v3 reference parser")
    fmt.eprintln("")
    fmt.eprintln("  usage: cslparser [MODE-FLAGS] [SEVERITY-FLAGS] [PRINT-FLAGS] <file>")
    fmt.eprintln("")
    fmt.eprintln("  mode flags:")
    fmt.eprintln("    --tokens | --lex      dump token stream")
    fmt.eprintln("    --errors              parse + print diagnostics only")
    fmt.eprintln("    --semantic            parse + semantic pass + summary")
    fmt.eprintln("    --print               pretty-print source")
    fmt.eprintln("    --roundtrip           parse \u2192 print \u2192 reparse \u2192 AST-shape check")
    fmt.eprintln("    --typecheck           T20 type-check + diagnostics")
    fmt.eprintln("    --ir                  T21 lower-to-IR and print MLIR-flavor dump")
    fmt.eprintln("                          composes: --ir --json  --ir --verify  --ir --verify --strict")
    fmt.eprintln("    (default)             parse + pretty-print AST (S-expression)")
    fmt.eprintln("")
    fmt.eprintln("  severity flags:")
    fmt.eprintln("    --lint                warn-only ; exit 0 ; editor-surface")
    fmt.eprintln("    --strict              any W or E \u2192 exit 1 (CI-gate)")
    fmt.eprintln("    --strict-parse        PERMISSIVE_ACCEPT \u2192 E (orthogonal)")
    fmt.eprintln("    --verbose | -v        surface Info diagnostics")
    fmt.eprintln("")
    fmt.eprintln("  print flags:")
    fmt.eprintln("    --mode=canonical|compact|literate|ascii-only|unicode-only")
}

dump_tokens :: proc(src: string, file: string) {
    tokens, errs := lex_source(src, file)
    for &t in tokens {
        pos := t.pos
        fmt.printf("%s:%d:%d  %-18s", file, pos.line, pos.col, token_kind_name(t.kind))
        if len(t.text) > 0 && t.kind != .Newline && t.kind != .Indent && t.kind != .Dedent && t.kind != .EOF {
            escaped := escape_text(t.text)
            fmt.printf(" %s", escaped)
        }
        fmt.println()
    }
    report_lex_errors(errs)
}

report_errors :: proc(lex_errs: []Lex_Error, parse_errs: []Parse_Error) {
    report_lex_errors(lex_errs)
    report_parse_errors(parse_errs)
}

report_lex_errors :: proc(errs: []Lex_Error) {
    for &e in errs {
        fmt.eprintf("%s:%d:%d: lex error: %s\n", e.pos.file, e.pos.line, e.pos.col, e.msg)
        if len(e.snippet) > 0 {
            fmt.eprintf("    %s\n", e.snippet)
            caret_pad(e.pos.col - 1)
        }
    }
}

report_parse_errors :: proc(errs: []Parse_Error) {
    for &e in errs {
        if len(e.context_) > 0 {
            fmt.eprintf("%s:%d:%d: parse error (%s): %s\n", e.pos.file, e.pos.line, e.pos.col, e.context_, e.msg)
        } else {
            fmt.eprintf("%s:%d:%d: parse error: %s\n", e.pos.file, e.pos.line, e.pos.col, e.msg)
        }
        if len(e.snippet) > 0 {
            fmt.eprintf("    %s\n", e.snippet)
            caret_pad(e.pos.col - 1)
        }
    }
}

caret_pad :: proc(n: int) {
    fmt.eprint("    ")
    for _ in 0 ..< n do fmt.eprint(" ")
    fmt.eprintln("^")
}

escape_text :: proc(s: string) -> string {
    sb := strings.builder_make(context.temp_allocator)
    for c in s {
        switch c {
        case '\n': strings.write_string(&sb, "\\n")
        case '\r': strings.write_string(&sb, "\\r")
        case '\t': strings.write_string(&sb, "\\t")
        case:      strings.write_rune(&sb, c)
        }
    }
    return strings.to_string(sb)
}

// =============================================================================
// T19 (Session-4) : `cssllint` subcommand — machine-readable diagnostics for
// CSSLv3 compiler embedding. See specs/14_CSSLv3_BRIDGE.csl §§ LINT-PROTOCOL.
// =============================================================================
//
// usage : parser cssllint [--json] [--strict] [--strict-parse] <file>
//
// text mode (default) : one diag per line, "file:line:col [sev] CODE msg"
// --json              : emit single JSON object with full diagnostics
//
// JSON schema :
//   {
//     "file":   <string>,
//     "status": "ok" | "warn" | "error",
//     "counts": { "info": N, "warn": N, "error": N },
//     "diags":  [
//       { "line":<int>, "col":<int>, "sev":"info"|"warn"|"error",
//         "code":<string>, "msg":<string> }
//     ]
//   }

cssllint_main :: proc(args: []string) {
    want_json := false
    sev := Sem_Mode.Default
    strict_parse := false
    file_path := ""
    for a in args {
        switch a {
        case "--json":          want_json = true
        case "--strict":        sev = .Strict
        case "--strict-parse":  strict_parse = true
        case "--lint":          sev = .Lint
        case "--help", "-h":
            fmt.eprintln("parser cssllint [--json] [--strict] [--strict-parse] <file>")
            os.exit(0)
        case:
            if strings.has_prefix(a, "--") {
                fmt.eprintf("cssllint: unknown option %s\n", a)
                os.exit(2)
            }
            file_path = a
        }
    }
    if len(file_path) == 0 {
        fmt.eprintln("cssllint: expected <file> argument")
        os.exit(2)
    }

    src_bytes, rerr := os.read_entire_file_from_path(file_path, context.allocator)
    if rerr != nil {
        if want_json {
            fmt.printf(
                `{{"file":"%s","status":"error","counts":{{"info":0,"warn":0,"error":1}},"diags":[{{"line":0,"col":0,"sev":"error","code":"CSL-E-IO","msg":"cannot read file: %v"}}]}}%s`,
                json_escape(file_path), rerr, "\n")
        } else {
            fmt.eprintf("cssllint: cannot read '%s': %v\n", file_path, rerr)
        }
        os.exit(1)
    }
    defer delete(src_bytes, context.allocator)
    src := string(src_bytes)

    doc, lex_errs, parse_errs := parse_source(src, file_path)
    res := semantic_analyze_with_mode(doc, sev, strict_parse)
    defer semantic_result_destroy(&res)

    // aggregate lex + parse + semantic diags into a unified flat list
    info_count, warn_count, err_count := semantic_counts(&res)
    err_count += len(lex_errs) + len(parse_errs)

    if want_json {
        fmt.printf(`{{"file":"%s","status":"`, json_escape(file_path))
        if err_count > 0 {
            fmt.print("error")
        } else if warn_count > 0 {
            fmt.print("warn")
        } else {
            fmt.print("ok")
        }
        fmt.printf(`","counts":{{"info":%d,"warn":%d,"error":%d}},"diags":[`,
            info_count, warn_count, err_count)
        first := true
        for &e in lex_errs {
            if !first do fmt.print(",")
            first = false
            fmt.printf(
                `{{"line":%d,"col":%d,"sev":"error","code":"CSL-E-LEX","msg":"%s"}}`,
                e.pos.line, e.pos.col, json_escape(e.msg))
        }
        for &e in parse_errs {
            if !first do fmt.print(",")
            first = false
            fmt.printf(
                `{{"line":%d,"col":%d,"sev":"error","code":"CSL-E-PARSE","msg":"%s"}}`,
                e.pos.line, e.pos.col, json_escape(e.msg))
        }
        for d in res.diagnostics {
            if !first do fmt.print(",")
            first = false
            sev_s := severity_label(d.severity)
            fmt.printf(
                `{{"line":%d,"col":%d,"sev":"%s","code":"%s","msg":"%s"}}`,
                d.pos.line, d.pos.col, sev_s, sem_code_name(d.code), json_escape(d.msg))
        }
        fmt.print("]}\n")
    } else {
        // text mode
        for &e in lex_errs {
            fmt.printf("%s:%d:%d [error] CSL-E-LEX %s\n", file_path, e.pos.line, e.pos.col, e.msg)
        }
        for &e in parse_errs {
            fmt.printf("%s:%d:%d [error] CSL-E-PARSE %s\n", file_path, e.pos.line, e.pos.col, e.msg)
        }
        for d in res.diagnostics {
            fmt.printf("%s:%d:%d [%s] %s %s\n",
                file_path, d.pos.line, d.pos.col,
                severity_label(d.severity), sem_code_name(d.code), d.msg)
        }
    }

    // exit-code rule : any error → 1 ; warn+strict → 1 ; else 0
    fails := err_count > 0 || (sev == .Strict && warn_count > 0) || (sev != .Lint && semantic_fails(&res))
    if fails do os.exit(1)
}

json_escape :: proc(s: string) -> string {
    sb := strings.builder_make(context.temp_allocator)
    for c in s {
        switch c {
        case '"':  strings.write_string(&sb, "\\\"")
        case '\\': strings.write_string(&sb, "\\\\")
        case '\n': strings.write_string(&sb, "\\n")
        case '\r': strings.write_string(&sb, "\\r")
        case '\t': strings.write_string(&sb, "\\t")
        case:
            if c < 0x20 {
                strings.write_string(&sb, fmt.tprintf("\\u%04x", i32(c)))
            } else {
                strings.write_rune(&sb, c)
            }
        }
    }
    return strings.to_string(sb)
}
