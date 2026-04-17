@echo off
REM § CSLv3 × Qwen3-Coder-Next HTTP-server mode (OpenAI-compatible)
REM I> binds localhost:8080 ; speaks OpenAI chat-completions schema
REM I> lets any client (Python / curl / VSCode Continue / etc.) call it
REM I> --parallel 1 ← single inference path to keep KV cache predictable

setlocal enabledelayedexpansion
cd /d "%~dp0\.."

set "LLAMA=D:\llama.cpp\llama-server.exe"
set "MODEL=D:\models\Qwen3-Coder-Next-UD-Q3_K_M.gguf"
set "SYSPROMPT=%CD%\qwen\system_prompt.txt"

if not exist "%LLAMA%" ( echo [ERROR] llama-server not at %LLAMA% & pause & exit /b 2 )
if not exist "%MODEL%" ( echo [ERROR] model not at %MODEL%     & pause & exit /b 2 )

echo ============================================================
echo   CSLv3 x Qwen3-Coder-Next 80B-A3B HTTP server
echo ============================================================
echo   bind   : http://127.0.0.1:8080
echo   model  : %MODEL%
echo   ctx    : 65536
echo.
echo   Test :  curl http://127.0.0.1:8080/v1/models
echo ============================================================

"%LLAMA%" ^
  --model        "%MODEL%" ^
  --system-prompt-file "%SYSPROMPT%" ^
  --ctx-size     65536 ^
  --n-gpu-layers 20 ^
  --cache-type-k q8_0 ^
  --cache-type-v q8_0 ^
  --host         127.0.0.1 ^
  --port         8080 ^
  --parallel     1 ^
  --alias        qwen3-coder-next

echo.
echo Server exited with code %ERRORLEVEL%
pause
