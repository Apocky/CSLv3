# diag_crash.ps1 -- collect post-crash diagnostics on Windows
# Run after a display glitch / black-screen event. Writes CSLv3\diag\<timestamp>.log
#
# Captures:
#   - Display/GPU driver events (last 4 hours)
#   - Application crashes (last 4 hours)
#   - Kernel-Power events (unexpected shutdowns / wake)
#   - Current GPU driver versions
#   - TDR registry settings
#   - Memory pressure snapshot
#   - Running process list

param(
    [int]$HoursBack = 4,
    [string]$OutDir = ".\diag"
)

$ErrorActionPreference = "SilentlyContinue"
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = Join-Path $OutDir "crash_$stamp.log"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Section($name) {
    "`n==================================================" | Out-File -Append -Encoding utf8 $outFile
    "  $name" | Out-File -Append -Encoding utf8 $outFile
    "==================================================" | Out-File -Append -Encoding utf8 $outFile
}

"CSLv3 CRASH DIAGNOSTIC -- $(Get-Date)" | Out-File -Encoding utf8 $outFile
"Window: last $HoursBack hours" | Out-File -Append -Encoding utf8 $outFile

# --- 1. display/driver events ---
Section "DISPLAY + DRIVER EVENTS (System log)"
$startTime = (Get-Date).AddHours(-$HoursBack)
$displayProviders = @(
    "Display", "nvlddmkm", "igdkmd64", "amdkmdag", "igdkmdn", "igdkmdnd",
    "Kernel-Pnp", "Kernel-Power", "Dxgkrnl", "BugCheck", "Schannel",
    "Microsoft-Windows-DriverFrameworks-UserMode"
)
$events = Get-WinEvent -FilterHashtable @{LogName = "System"; StartTime = $startTime} 2>$null |
    Where-Object { $displayProviders -contains $_.ProviderName -or $_.Message -match "TDR|timeout|display|graphics" }
if ($events) {
    $events | ForEach-Object {
        "[{0}] {1} Id={2} Level={3}" -f $_.TimeCreated, $_.ProviderName, $_.Id, $_.LevelDisplayName | Out-File -Append -Encoding utf8 $outFile
        "  " + ($_.Message -replace "`r?`n", " | ") | Out-File -Append -Encoding utf8 $outFile
    }
} else {
    "  (none)" | Out-File -Append -Encoding utf8 $outFile
}

# --- 2. application crashes ---
Section "APPLICATION CRASHES (Application log, WER)"
$appEvents = Get-WinEvent -FilterHashtable @{LogName = "Application"; StartTime = $startTime} 2>$null |
    Where-Object { $_.LevelDisplayName -eq "Error" -or $_.ProviderName -match "Application Error|WER|\.NET Runtime" }
if ($appEvents) {
    $appEvents | Select-Object -First 30 | ForEach-Object {
        "[{0}] {1} Id={2} Level={3}" -f $_.TimeCreated, $_.ProviderName, $_.Id, $_.LevelDisplayName | Out-File -Append -Encoding utf8 $outFile
        "  " + ($_.Message -replace "`r?`n", " | ") | Out-File -Append -Encoding utf8 $outFile
    }
} else {
    "  (none)" | Out-File -Append -Encoding utf8 $outFile
}

# --- 3. unexpected shutdowns ---
Section "UNEXPECTED SHUTDOWNS / WAKE EVENTS"
$powerEvents = Get-WinEvent -FilterHashtable @{LogName = "System"; StartTime = $startTime; Id = 41, 6008, 1074} 2>$null
if ($powerEvents) {
    $powerEvents | ForEach-Object {
        "[{0}] {1} Id={2}" -f $_.TimeCreated, $_.ProviderName, $_.Id | Out-File -Append -Encoding utf8 $outFile
        "  " + ($_.Message -replace "`r?`n", " | ") | Out-File -Append -Encoding utf8 $outFile
    }
} else {
    "  (none -- clean)" | Out-File -Append -Encoding utf8 $outFile
}

# --- 4. driver versions ---
Section "GPU DRIVER VERSIONS"
try {
    Get-CimInstance Win32_VideoController | ForEach-Object {
        "Name:    $($_.Name)" | Out-File -Append -Encoding utf8 $outFile
        "Driver:  $($_.DriverVersion)  ($($_.DriverDate))" | Out-File -Append -Encoding utf8 $outFile
        "Memory:  $([math]::Round($_.AdapterRAM / 1MB, 0)) MB" | Out-File -Append -Encoding utf8 $outFile
        "Status:  $($_.Status)" | Out-File -Append -Encoding utf8 $outFile
        "" | Out-File -Append -Encoding utf8 $outFile
    }
} catch {
    "  (Get-CimInstance failed: $_)" | Out-File -Append -Encoding utf8 $outFile
}

# --- 5. TDR registry settings ---
Section "TDR REGISTRY (HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers)"
$tdrKey = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
try {
    $tdrProps = Get-ItemProperty -Path $tdrKey
    "TdrLevel:   $($tdrProps.TdrLevel)   (default 3 = recover+bugcheck)" | Out-File -Append -Encoding utf8 $outFile
    "TdrDelay:   $($tdrProps.TdrDelay)   (default 2 seconds)" | Out-File -Append -Encoding utf8 $outFile
    "TdrDdiDelay: $($tdrProps.TdrDdiDelay)  (default 5 seconds)" | Out-File -Append -Encoding utf8 $outFile
    "TdrDebugMode: $($tdrProps.TdrDebugMode)" | Out-File -Append -Encoding utf8 $outFile
} catch {
    "  (read failed: $_)" | Out-File -Append -Encoding utf8 $outFile
}

# --- 6. memory pressure snapshot ---
Section "MEMORY PRESSURE"
try {
    $os = Get-CimInstance Win32_OperatingSystem
    "TotalVisibleMemory: $([math]::Round($os.TotalVisibleMemorySize / 1KB, 0)) MB" | Out-File -Append -Encoding utf8 $outFile
    "FreePhysicalMemory: $([math]::Round($os.FreePhysicalMemory / 1KB, 0)) MB" | Out-File -Append -Encoding utf8 $outFile
    "TotalVirtualMemory: $([math]::Round($os.TotalVirtualMemorySize / 1KB, 0)) MB" | Out-File -Append -Encoding utf8 $outFile
    "FreeVirtualMemory:  $([math]::Round($os.FreeVirtualMemory / 1KB, 0)) MB" | Out-File -Append -Encoding utf8 $outFile
} catch {}

# --- 7. top memory processes (at diag run time) ---
Section "TOP 15 PROCESSES BY MEMORY (at diag run time)"
Get-Process | Sort-Object WS -Descending | Select-Object -First 15 |
    Format-Table -AutoSize Name, Id, @{Name="WS_MB"; Expression={[math]::Round($_.WS/1MB,0)}}, CPU, StartTime |
    Out-String -Width 200 | Out-File -Append -Encoding utf8 $outFile

# --- 8. recent odin/parser events from our session ---
Section "RECENT ODIN / PARSER PROCESS TRACES"
Get-WinEvent -FilterHashtable @{LogName = "Application"; StartTime = $startTime} 2>$null |
    Where-Object { $_.Message -match "odin\.exe|parser\.exe|link\.exe|LLVM" } |
    ForEach-Object {
        "[{0}] {1} Id={2}" -f $_.TimeCreated, $_.ProviderName, $_.Id | Out-File -Append -Encoding utf8 $outFile
        "  " + ($_.Message -replace "`r?`n", " | ") | Out-File -Append -Encoding utf8 $outFile
    }

"`n--- END OF DIAGNOSTIC -- $(Get-Date) ---" | Out-File -Append -Encoding utf8 $outFile
Write-Host "Diagnostic written to: $outFile"
