package cslparser

// § CSLv3 SMT SOLVER DRIVER (T26.f Session-7)
// I> invokes Z3 / CVC5 as external process ; SMT-LIB2 via tempfile
// I> graceful-degrade : no-solver → Skipped result ; never-crash
// I> timeout-enforced : per-solver -T:/--tlimit flag
// I> response-parsing : first non-comment line determines result ;
//                       "sat" | "unsat" | "unknown" | "timeout"
// R! ← handoff §§ DISCHARGE-ALGORITHM §§ CLI-SURFACE

import "core:fmt"
import "core:os"
import "core:strings"

// ---------- Solver availability probe ----------

solver_available :: proc(name, path: string) -> bool {
    if len(path) == 0 do return false
    return os.exists(path)
}

solver_version :: proc(name, path: string) -> string {
    if !solver_available(name, path) do return ""
    args: [dynamic]string
    defer delete(args)
    append(&args, path)
    switch name {
    case "z3":   append(&args, "-version")
    case "cvc5": append(&args, "--version")
    }
    state, stdout, stderr, err := os.process_exec(os.Process_Desc{
        command = args[:],
    }, context.allocator)
    defer delete(stdout, context.allocator)
    defer delete(stderr, context.allocator)
    _ = stderr
    _ = state
    if err != nil do return ""
    line := first_line(string(stdout))
    return strings.clone(strings.trim_space(line))
}

// ---------- Core invocation ----------
// `name`   : "z3" | "cvc5"
// `script` : canonical SMT-LIB2 text
// returns (result, true) on successful invocation, (Error, false) on failure

solve_with :: proc(name, script_text: string, timeout_ms: int, solver_path_: string) -> (Smt_Result, bool) {
    if !solver_available(name, solver_path_) do return .Error, false

    // 1. write tempfile
    tmp, terr := write_temp_smt2(script_text, name)
    if terr != "" do return .Error, false
    defer os.remove(tmp)

    // 2. build argv
    args: [dynamic]string
    defer delete(args)
    append(&args, solver_path_)
    switch name {
    case "z3":
        append(&args, fmt.tprintf("-T:%d", (timeout_ms + 999) / 1000))   // seconds
        append(&args, "-smt2")
        append(&args, tmp)
    case "cvc5":
        append(&args, fmt.tprintf("--tlimit=%d", timeout_ms))
        append(&args, "--lang=smt2")
        append(&args, tmp)
    case:
        return .Error, false
    }

    // 3. invoke
    state, stdout, stderr, err := os.process_exec(os.Process_Desc{
        command = args[:],
    }, context.allocator)
    defer delete(stdout, context.allocator)
    defer delete(stderr, context.allocator)
    _ = stderr
    _ = state

    if err != nil do return .Error, false

    // 4. parse response
    return parse_solver_response(string(stdout)), true
}

// ---------- Response parser ----------
// SMT-LIB2 response : one status word per (check-sat), possibly followed by
// (get-model) output or (get-unsat-core) output. We only care about the
// first non-comment word.

parse_solver_response :: proc(out: string) -> Smt_Result {
    remaining := out
    for len(remaining) > 0 {
        nl_idx := strings.index_byte(remaining, '\n')
        ln: string
        if nl_idx < 0 {
            ln = remaining
            remaining = ""
        } else {
            ln = remaining[:nl_idx]
            remaining = remaining[nl_idx+1:]
        }
        t := strings.trim_space(ln)
        if len(t) == 0 do continue
        if strings.has_prefix(t, ";") do continue
        // Z3 sometimes prefixes with warnings, e.g. "WARNING: ..."
        if strings.has_prefix(t, "WARNING:") do continue
        if strings.has_prefix(t, "warning:") do continue
        // strip stray leading "("
        switch {
        case strings.has_prefix(t, "unsat"):   return .Unsat
        case strings.has_prefix(t, "sat"):     return .Sat
        case strings.has_prefix(t, "unknown"):
            // Z3 output on timeout : "unknown" then "(:reason-unknown timeout)"
            if strings.contains(out, "timeout") do return .Timeout
            return .Unknown
        case strings.has_prefix(t, "timeout"): return .Timeout
        case strings.has_prefix(t, "(error"):  return .Error
        }
    }
    return .Unknown
}

// ---------- Temp-file helpers ----------

@(private="file")
write_temp_smt2 :: proc(body: string, solver_name: string) -> (string, string) {
    // Put the tempfile in the user-temp dir. We name it distinctively so
    // parallel invocations don't collide (microsecond + pid).
    base := os.get_env("TEMP", context.allocator)
    if len(base) == 0 do base = os.get_env("TMP", context.allocator)
    if len(base) == 0 do base = "/tmp"
    // Odin's os.get_env may return either nil or owned — handle both
    defer if len(base) > 0 do delete(base, context.allocator)

    name := fmt.tprintf("%s%scslv3_%s_%d_%d.smt2",
                        base, "/", solver_name, temp_counter_next(), time_now_ms())
    ok := os.write_entire_file(name, transmute([]byte)body)
    if ok != nil do return "", "write-failed"
    return strings.clone(name), ""
}

// os.get_env returns `string, bool` in some Odin versions ; provide a tiny
// placeholder so this compiles against the current core. If the API differs,
// fall back to "" and the temp-dir becomes cwd.

// ---------- Misc helpers ----------

@(private="file")
first_line :: proc(s: string) -> string {
    for i := 0; i < len(s); i += 1 {
        if s[i] == '\n' || s[i] == '\r' do return s[:i]
    }
    return s
}

// PID proxy : Odin's core has no portable get_pid at this layer ;
// the tempfile name uses a monotonic-counter instead to avoid collisions.
@(private="file")
g_temp_counter: int = 0

@(private="file")
temp_counter_next :: proc() -> int {
    g_temp_counter += 1
    return g_temp_counter
}
