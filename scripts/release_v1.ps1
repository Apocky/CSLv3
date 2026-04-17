# § CSLv3 v1.0 release-automation (PowerShell wrapper) (Session-10+)
# I> Delegates to scripts\release_v1.sh via Git-Bash so WSL isn't required
# I> --DoRelease switch required for live run (matches .sh --do-release)
# I> Searches for Git-Bash in known locations ; falls back to wsl if-only

[CmdletBinding()]
param(
    [switch]$DoRelease,
    [string]$BashPath = ""
)

$ErrorActionPreference = "Stop"
$ScriptRoot  = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot    = Split-Path -Parent $ScriptRoot
$ShScript    = Join-Path $ScriptRoot "release_v1.sh"

if (-not (Test-Path $ShScript)) {
    Write-Error "release_v1.sh not found at $ShScript"
    exit 2
}

# ---------- locate Git-Bash (avoid WSL path) ----------
function Find-GitBash {
    if ($BashPath -and (Test-Path $BashPath)) { return $BashPath }
    $candidates = @(
        "C:\Program Files\Git\bin\bash.exe",
        "C:\Program Files (x86)\Git\bin\bash.exe",
        "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe",
        "$env:USERPROFILE\AppData\Local\Programs\Git\bin\bash.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }
    # Last resort : wherever `where.exe bash` resolves BUT skip the WSL shim
    $w = (where.exe bash 2>$null) | Where-Object { $_ -notmatch 'System32' }
    if ($w) { return $w[0] }
    return $null
}

$bash = Find-GitBash
if (-not $bash) {
    Write-Error "Git-Bash not found. Install Git for Windows (gitforwindows.org) or pass -BashPath <path>."
    exit 2
}

Write-Host "§ using bash: $bash" -ForegroundColor Cyan

# ---------- invoke ----------
$args = @($ShScript)
if ($DoRelease) { $args += "--do-release" }

Push-Location $RepoRoot
try {
    & $bash @args
    $rc = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($rc -ne 0) {
    Write-Error "release_v1.sh exited $rc"
    exit $rc
}

Write-Host "§ release_v1.sh $($DoRelease ? 'LIVE' : 'DRY-RUN') complete (rc=0)" -ForegroundColor Green
