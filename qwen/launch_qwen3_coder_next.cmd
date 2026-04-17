@echo off
REM § CSLv3 × Qwen3-Coder-Next 80B-A3B launcher (Session-11 kickoff)
REM I> uses llama.cpp Vulkan backend on Intel Arc A770
REM I> ctx=65536 = practical ceiling on 16GB VRAM + 32GB RAM
REM I> system-prompt pre-loaded from qwen/system_prompt.txt
REM I> 3B active params → faster than dense 14B despite 80B total

setlocal enabledelayedexpansion
cd /d "%~dp0\.."

set "LLAMA=D:\llama.cpp\llama-cli.exe"
set "MODEL=D:\models\Qwen3-Coder-Next-UD-Q3_K_M.gguf"
set "SYSPROMPT=%CD%\qwen\system_prompt.txt"

if not exist "%LLAMA%"     ( echo [ERROR] llama-cli not at %LLAMA%     & pause & exit /b 2 )
if not exist "%MODEL%"     ( echo [ERROR] model not at %MODEL%        & pause & exit /b 2 )
if not exist "%SYSPROMPT%" ( echo [ERROR] system-prompt not at %SYSPROMPT% & pause & exit /b 2 )

REM Layer-offload tuning for 80B MoE on 16GB Arc :
REM   --n-gpu-layers 20  puts ~20 layers on GPU ; rest on CPU
REM   --split-mode layer is the default ; explicit for clarity
REM   --cache-type-k q8_0 + --cache-type-v q8_0 halves KV footprint
REM   --ctx-size 65536 = 64K ctx (128K would exceed 48GB total memory)
REM   --temp 0.7 + --top-p 0.8 = Qwen-Coder recommended sampling
REM   --repeat-penalty 1.05 mild anti-loop

echo ============================================================
echo   CSLv3 x Qwen3-Coder-Next 80B-A3B (UD-Q3_K_M)
echo ============================================================
echo   model   : %MODEL%
echo   ctx     : 65536 tokens (~64K)
echo   GPU     : Intel Arc A770 via Vulkan
echo   prompt  : %SYSPROMPT%
echo ============================================================
echo.

"%LLAMA%" ^
  --model        "%MODEL%" ^
  --system-prompt-file "%SYSPROMPT%" ^
  --ctx-size     65536 ^
  --n-gpu-layers 20 ^
  --cache-type-k q8_0 ^
  --cache-type-v q8_0 ^
  --temp         0.7 ^
  --top-p        0.8 ^
  --top-k        20 ^
  --repeat-penalty 1.05 ^
  --color ^
  --conversation ^
  %*

echo.
echo ============================================================
echo   Session ended. Exit code = %ERRORLEVEL%
echo ============================================================
pause
