@echo off
REM § One-click CSL3×Qwen launcher menu
REM I> double-click OR `.\qwen\qwen.cmd` from PowerShell
REM I> picks between 80B (quality) / 14B-YaRN-1M (long-ctx) / server mode / validation-loop

setlocal enabledelayedexpansion
cd /d "%~dp0\.."

set "MODEL_80B=D:\models\Qwen3-Coder-Next-UD-Q3_K_M.gguf"
set "MODEL_14B=D:\models\Qwen3-14B-Q4_K_M.gguf"

:menu
cls
echo ============================================================
echo   CSLv3 x Qwen3 launcher
echo ============================================================
if exist "%MODEL_80B%" (echo   [OK] 80B model at %MODEL_80B%) else (echo   [MISSING] 80B model)
if exist "%MODEL_14B%" (echo   [OK] 14B model at %MODEL_14B%) else (echo   [MISSING] 14B model)
echo ============================================================
echo.
echo   1. Chat with Qwen3-Coder-Next 80B-A3B    (quality ; 64K ctx)
echo   2. Chat with Qwen3-14B @ YaRN 1M ctx     (long-ctx ; 1M)
echo   3. Start HTTP server (80B OpenAI-api)    (bind 127.0.0.1:8080)
echo   4. Rebuild system prompt from specs
echo   5. Run validation loop (requires #3 running in another window)
echo   Q. QUIT
echo.
set /p "CHOICE=Select : "

if /i "%CHOICE%"=="1" ( call qwen\launch_qwen3_coder_next.cmd & goto :menu )
if /i "%CHOICE%"=="2" ( call qwen\launch_qwen3_14b_yarn1m.cmd   & goto :menu )
if /i "%CHOICE%"=="3" ( call qwen\serve_qwen3_coder_next.cmd    & goto :menu )
if /i "%CHOICE%"=="4" (
    python qwen\build_system_prompt.py
    pause
    goto :menu
)
if /i "%CHOICE%"=="5" (
    python qwen\validate_loop.py --interactive
    pause
    goto :menu
)
if /i "%CHOICE%"=="Q" goto :quit

echo Invalid choice.
timeout /t 1 /nobreak >nul
goto :menu

:quit
exit /b 0
