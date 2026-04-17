# § CSLv3 T26 SMT-solver installer (Session-7)
# I> installs Z3 via chocolatey ; CVC5 pre-built from GitHub release
# I> idempotent : skips if already-installed
# I> run : powershell -ExecutionPolicy Bypass -File scripts\install_solvers.ps1
# N! requires Administrator for choco install

param(
    [switch]$SkipZ3 = $false,
    [switch]$SkipCVC5 = $false,
    [string]$CVC5Version = "1.3.0"
)

$ErrorActionPreference = "Continue"

Write-Host "=== CSLv3 T26 SMT-solver installer ===" -ForegroundColor Cyan

# ---------- Z3 via chocolatey ----------
if (-not $SkipZ3) {
    Write-Host "`n[1/2] Checking Z3..." -ForegroundColor Yellow
    $z3 = Get-Command z3 -ErrorAction SilentlyContinue
    if ($z3) {
        Write-Host "  z3 already on PATH: $($z3.Source)" -ForegroundColor Green
        & z3 -version
    } else {
        $choco = Get-Command choco -ErrorAction SilentlyContinue
        if (-not $choco) {
            Write-Host "  ERROR: choco not found. Install Chocolatey first:" -ForegroundColor Red
            Write-Host "    https://chocolatey.org/install" -ForegroundColor Red
        } else {
            Write-Host "  Installing z3 via choco (requires Administrator)..." -ForegroundColor Yellow
            & choco install z3 -y
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  z3 installed." -ForegroundColor Green
            } else {
                Write-Host "  z3 install failed (rc=$LASTEXITCODE)" -ForegroundColor Red
            }
        }
    }
}

# ---------- CVC5 via GitHub release ----------
if (-not $SkipCVC5) {
    Write-Host "`n[2/2] Checking CVC5..." -ForegroundColor Yellow
    $cvc5 = Get-Command cvc5 -ErrorAction SilentlyContinue
    if ($cvc5) {
        Write-Host "  cvc5 already on PATH: $($cvc5.Source)" -ForegroundColor Green
        & cvc5 --version | Select-Object -First 1
    } else {
        $installDir = "$env:LOCALAPPDATA\cvc5"
        $exePath = "$installDir\cvc5.exe"
        if (Test-Path $exePath) {
            Write-Host "  cvc5 found at $exePath (add to PATH manually)" -ForegroundColor Green
        } else {
            # cvc5 release URL format :
            # https://github.com/cvc5/cvc5/releases/download/cvc5-1.3.0/cvc5-Win64-x86_64-static.zip
            $releaseUrl = "https://github.com/cvc5/cvc5/releases/download/cvc5-$CVC5Version/cvc5-Win64-x86_64-static.zip"
            $zipPath = "$env:TEMP\cvc5.zip"
            New-Item -ItemType Directory -Force -Path $installDir | Out-Null
            Write-Host "  Downloading $releaseUrl ..." -ForegroundColor Yellow
            try {
                Invoke-WebRequest -Uri $releaseUrl -OutFile $zipPath -UseBasicParsing
                Write-Host "  Extracting to $installDir..." -ForegroundColor Yellow
                Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
                # the zip unpacks to cvc5-Win64-x86_64-static\bin\cvc5.exe
                $inner = Get-ChildItem -Path $installDir -Filter "cvc5.exe" -Recurse -File |
                         Select-Object -First 1
                if ($inner) {
                    Copy-Item $inner.FullName $exePath -Force
                    Write-Host "  cvc5 installed to $exePath" -ForegroundColor Green
                    Write-Host "  Add $installDir to PATH, or pass --cvc5=$exePath" -ForegroundColor Cyan
                    & $exePath --version | Select-Object -First 1
                } else {
                    Write-Host "  ERROR: cvc5.exe not found in extracted zip" -ForegroundColor Red
                }
                Remove-Item $zipPath -ErrorAction SilentlyContinue
            } catch {
                Write-Host "  cvc5 download/extract failed: $_" -ForegroundColor Red
                Write-Host "  Manual download: https://github.com/cvc5/cvc5/releases" -ForegroundColor Yellow
            }
        }
    }
}

Write-Host "`n=== Done ===" -ForegroundColor Cyan
Write-Host "Test : parser.exe --smt-selftest --z3=<path>" -ForegroundColor Gray
