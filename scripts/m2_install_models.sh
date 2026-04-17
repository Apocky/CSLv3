#!/usr/bin/env bash
# § T25.1 — m₂ model bootstrap (Session-11)
# I> downloads 3 reference GGUFs (~7 GB total) via huggingface_hub
# I> cache-dir : $CSLV3_M2_CACHE  (default : ~/.cslv3-m2-models/)
# I> idempotent : skips already-verified models
# I> llama-cpp-python required for inference (installed separately)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE="${CSLV3_M2_CACHE:-$HOME/.cslv3-m2-models}"

echo "§ T25 m₂ model bootstrap"
echo "  cache : $CACHE"
echo

# 1. Ensure Python + huggingface_hub
if ! command -v python >/dev/null; then
    echo "[fatal] python not on PATH" >&2
    exit 2
fi

if ! python -c "import huggingface_hub" 2>/dev/null; then
    echo "[install] huggingface_hub + hf-transfer"
    python -m pip install --quiet huggingface_hub hf-transfer
fi

if ! python -c "import llama_cpp" 2>/dev/null; then
    echo "[install] llama-cpp-python (may take a few minutes ; builds natively)"
    echo "  tip : on Intel Arc use CMAKE_ARGS='-DGGML_VULKAN=ON' for GPU"
    python -m pip install --quiet llama-cpp-python || {
        echo "[warn] llama-cpp-python install failed ; T25 harness will use mock-model fallback only"
    }
fi

# 2. Download models via the registry
echo
echo "§ downloading reference models"
python "$SCRIPT_DIR/m2_models.py" download "$@"

echo
echo "§ verify"
python "$SCRIPT_DIR/m2_models.py" verify

echo
echo "§ done. Cache at: $CACHE"
echo "  test: python scripts/compute_m2.py --self-test"
