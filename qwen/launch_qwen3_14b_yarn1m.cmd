@echo off
REM § CSLv3 × Qwen3-14B dense @ YaRN-extended 1M context
REM I> fits entirely in 16GB VRAM ; full-GPU offload ; fast tok/s
REM I> YaRN scaling : factor=4 extends 256K native → 1M effective
REM I> use this when you need long-context CSL3 ingest (whole spec + session)

setlocal enabledelayedexpansion
cd /d "%~dp0\.."

set "LLAMA=D:\llama.cpp\llama-cli.exe"
set "MODEL=D:\models\Qwen3-14B-Q4_K_M.gguf"
set "SYSPROMPT=%CD%\qwen\system_prompt.txt"

if not exist "%LLAMA%"     ( echo [ERROR] llama-cli not at %LLAMA%     & pause & exit /b 2 )
if not exist "%MODEL%"     ( echo [ERROR] model not at %MODEL%        & pause & exit /b 2 )
if not exist "%SYSPROMPT%" ( echo [ERROR] system-prompt not at %SYSPROMPT% & pause & exit /b 2 )

REM YaRN-RoPE-extension :
REM   --rope-scaling yarn      enables YaRN (not linear/dynamic)
REM   --rope-scale 4.0         4× the 256K native → 1,048,576 ctx
REM   --yarn-orig-ctx 262144   tells it where native ctx ended
REM Q4_K_M KV quant to keep the 1M KV-cache inside 16GB VRAM

echo ============================================================
echo   CSLv3 x Qwen3-14B @ YaRN 1M context
echo ============================================================
echo   model   : %MODEL%
echo   ctx     : 1048576 tokens (1M via YaRN ; native=256K)
echo   GPU     : Intel Arc A770 via Vulkan (full offload)
echo   prompt  : %SYSPROMPT%
echo ============================================================
echo.

"%LLAMA%" ^
  --model        "%MODEL%" ^
  --system-prompt-file "%SYSPROMPT%" ^
  --ctx-size     1048576 ^
  --n-gpu-layers 99 ^
  --rope-scaling yarn ^
  --rope-scale   4.0 ^
  --yarn-orig-ctx 262144 ^
  --cache-type-k q4_0 ^
  --cache-type-v q4_0 ^
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
