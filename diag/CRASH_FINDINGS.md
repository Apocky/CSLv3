# Crash Findings — 2026-04-16

## Confirmed: FULL SYSTEM CRASHES, not display glitches

The display symptoms (main monitor black, secondary white) were the visible face of **unexpected full-system reboots**. Windows logged two `Kernel-Power Event ID 41` events during this session:

| time | event | previous clean shutdown |
|------|-------|--------------------------|
| 11:40:29 AM | System rebooted without clean shutdown | 11:02:56 AM |
| 12:05:10 PM | System rebooted without clean shutdown | 11:40:38 AM |

Between 11:02 and 11:40 the system ran for ~37 min before crash #1. Between 11:40 and 12:05 it ran ~25 min before crash #2.

## Preceding symptom

At 11:38:39 AM — 2 minutes before crash #1 — **DWM (Desktop Window Manager) crashed**:

```
Faulting application:  dwm.exe  (10.0.26100.8115)
Faulting module:       dwmcore.dll  (10.0.26100.8246)
Exception code:        0xc00001ad   (STATUS_FATAL_USER_CALLBACK_EXCEPTION)
```

DWM crashing with that exception is typically driver-level — usually a GPU driver issue or a third-party display hook misbehaving.

## System context

```
GPU:   Intel(R) Arc(TM) A770 Graphics
       Driver 32.0.101.8331 (2025-11-25)

Other display adapters installed:
  - SudoMaker Virtual Display Adapter (driver 11.32.31.978)
  - Parsec Virtual Display Adapter (driver 0.45.0.0 from 2024-01)
```

Both crashes were followed by **"Intel Platform License Manager Service" timeout (45 seconds)** on boot — a known Intel driver-stack timing issue, not necessarily the cause.

## NOT caused by the parser work

The Odin parser I was building does not touch GPU, display, or kernel. It's a pure CPU/CLI tool. What it COULD plausibly stress:

- CPU + RAM during `odin build` (LLVM + MSVC linker)
- PCIe/disk I/O during link

**Plausible cause chain** (not proven):

1. Odin build spikes CPU load → system-wide power draw increases
2. GPU driver or firmware gets starved for scheduling time → display stack hiccups
3. DWM faults → system loses graphics
4. Kernel panics without display → looks like "black screen"
5. Watchdog reboots → Event ID 41

This is consistent with Intel Arc A770 + certain motherboards showing TDR/reset issues under combined CPU+GPU load, but **the real culprit needs further investigation**.

## Recommendations for Apocky

**Driver + firmware:**

1. Update Intel Arc driver to latest from Intel Arc Control. Current `32.0.101.8331` is from 2025-11-25; newer builds exist.
2. Update motherboard BIOS if one is available (12-14th gen Intel boards have had AVX2 + P/E-core scheduling fixes throughout 2025-26).
3. If you don't actively use them, uninstall **Parsec Virtual Display Adapter** and **SudoMaker Virtual Display Adapter** — extra display drivers in the stack multiply failure modes.

**Hardware sanity:**

4. Run `mdsched.exe` (Windows Memory Diagnostic) next reboot — rules out RAM.
5. Check CPU + GPU temps during heavy work. HWiNFO64 or Intel XTU for CPU, Arc Control for GPU. If CPU hits 100°C under Odin link, thermal throttle is real.
6. Arc A770 needs a **750W+ 80+ Gold** PSU with quality 12th/13th/14th-gen Intel CPUs. If the PSU is older/cheaper, under sustained CPU+GPU spikes it may sag and cause resets with no blue screen.

**Workflow mitigation (what I'll do):**

7. **Minimize Odin rebuilds.** I've been rebuilding after almost every edit. Going forward: batch edits, build once at logical checkpoints.
8. **Always write state to disk before a compile** — `DECISIONS.md` gets updated before any `odin build`, so a mid-build crash loses nothing.
9. **Run `safer_build.sh`** instead of raw `odin build` — it kills stale processes, checks memory, and auto-invokes `diag_crash.ps1` on failure.

## Diagnostic tooling created this session

- [scripts/diag_crash.ps1](../scripts/diag_crash.ps1) — collects Windows event logs, driver versions, TDR registry state, memory snapshot, process list. Run after any display glitch.
- [scripts/safer_build.sh](../scripts/safer_build.sh) — wraps `odin build` with pre-check + timing + auto-diag on failure.
- [scripts/README.md](../scripts/README.md) — usage + methodology notes.
- `diag/crash_<timestamp>.log` — raw event dumps (one per run).

## Verdict

Not a Claude Code bug. Not a parser bug. Likely GPU-driver or power-delivery under sustained CPU load. Update drivers first. If it recurs with fresh drivers, escalate to hardware diagnostics.
