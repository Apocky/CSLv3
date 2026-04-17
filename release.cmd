@echo off
REM § CSLv3 one-click release launcher
REM I> double-click from Explorer OR run `.\release.cmd` in PowerShell
REM I> bypasses WSL + finds Git-Bash automatically + asks dry/live

setlocal enabledelayedexpansion
cd /d "%~dp0"

set "BASH="
for %%P in (
    "C:\Program Files\Git\bin\bash.exe"
    "C:\Program Files (x86)\Git\bin\bash.exe"
    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
) do (
    if exist %%~P (
        set "BASH=%%~P"
        goto :found
    )
)
echo.
echo [ERROR] Git-Bash not found.
echo Install Git for Windows : https://gitforwindows.org
echo.
pause
exit /b 2

:found
echo.
echo ============================================================
echo   CSLv3 v1.0 Release Launcher
echo ============================================================
echo   bash    : %BASH%
echo   repo    : %CD%
for /f "usebackq delims=" %%V in ("%CD%\VERSION") do set "VER=%%V"
echo   version : %VER%
echo ============================================================
echo.
echo   1. DRY-RUN   (safe preview ; no changes)
echo   2. LIVE      (actually tag + build + bundle)
echo   Q. QUIT
echo.
set /p "CHOICE=Select (1/2/Q) : "

if /i "%CHOICE%"=="1" goto :dryrun
if /i "%CHOICE%"=="2" goto :live
if /i "%CHOICE%"=="Q" goto :quit

echo.
echo Invalid choice. Exiting.
pause
exit /b 2

:dryrun
echo.
echo [running DRY-RUN]
echo.
"%BASH%" scripts/release_v1.sh
goto :end

:live
echo.
echo [!] LIVE release will tag git v%VER% + build artifacts.
set /p "CONFIRM=Type YES to confirm : "
if /i not "%CONFIRM%"=="YES" (
    echo.
    echo Cancelled.
    pause
    exit /b 0
)
echo.
echo [running LIVE release]
echo.
"%BASH%" scripts/release_v1.sh --do-release
goto :end

:quit
echo.
echo Cancelled.
exit /b 0

:end
echo.
echo ============================================================
echo   Done. Exit code = %ERRORLEVEL%
echo ============================================================
pause
