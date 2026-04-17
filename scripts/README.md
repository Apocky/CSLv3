# scripts/ — diagnostic + methodology tooling

Created 2026-04-16 after two suspicious display glitches during Odin build.

## diag_crash.ps1

Post-crash Windows diagnostic collector. Writes `diag/crash_<stamp>.log` containing:

- Last 4 hours of display/driver events (Dxgkrnl, nvlddmkm, igdkmd, amdkmdag, Kernel-Pnp, Kernel-Power, BugCheck)
- Application-log errors (WER, `.NET Runtime`, etc.)
- Unexpected-shutdown events (Event IDs 41, 6008, 1074)
- Installed GPU adapters + driver versions + dates
- TDR registry settings (`TdrLevel`, `TdrDelay`, `TdrDdiDelay`, `TdrDebugMode`)
- Current physical + virtual memory
- Top 15 processes by working-set size
- Any `odin.exe` / `parser.exe` / `link.exe` events in the window

Run from repo root after a display glitch:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts/diag_crash.ps1
```

Attach the resulting `diag/crash_*.log` to any bug report. Look especially for:

- **Event ID 4101** (Dxgkrnl) — "Display driver stopped responding and has recovered" → TDR event
- **Event ID 117** (Dxgkrnl) — "GPU TDR event" (newer wording)
- **Event ID 41** (Kernel-Power) — unexpected shutdown without BSOD
- **TdrDelay < 2** — delay too short; GPU resets under normal load

## safer_build.sh

Wrapper around `odin build parser/` that:

1. Kills any running `parser.exe` (it locks the output file).
2. Checks free physical memory and warns if < 1 GB.
3. Runs the compile with full output teed to `diag/build_<stamp>.log`.
4. On failure, auto-invokes `diag_crash.ps1` for the same time window.
5. Sanity-checks the resulting binary.

Use it instead of raw `odin build parser/` when iterating:

```bash
./scripts/safer_build.sh
```

## Working methodology (post-incident)

- **Compile only when stable**, not after every edit. The parser is ~1800 lines of Odin; LLVM+MSVC linking is non-trivial work.
- **Persist state to disk before any compile** — edits, notes, DECISIONS.md — so a crash mid-build loses nothing.
- **After a crash**, immediately run `diag_crash.ps1` — the 4-hour window catches the event even if Windows takes a minute to flush logs.
- **Graceful Odin errors**: the Odin compiler already emits structured error messages to stderr. Those are captured by `safer_build.sh`. Runtime panics in the parser itself are rare (Odin has bounds checking in debug mode) but can be caught by running `parser.exe` under a debugger if needed.
- **GPU driver hygiene**: Intel Arc A770 has known TDR issues under PCIe bandwidth spikes. Keep driver up to date (Arc Control auto-updates). If crashes persist, consider raising `TdrDelay` from 2→8 seconds via registry — though this masks real driver bugs rather than fixing them.

## Not implemented here (by design)

- No automated crash-recovery in the parser itself. It's a short-lived CLI; there's nothing to recover. The diagnostic value comes from Windows event logs, not the parser's own state.
- No GPU driver install/update — done via vendor utility (Intel Arc Control / NVIDIA GeForce Experience), not by scripts.
