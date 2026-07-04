#!/bin/sh
# fuse_and_convert.sh - adapter -> GGUF merge/convert path (documented + attempted).
#
# Step 1 (merge): mlx_lm.fuse merges the LoRA adapter into the base weights
#                 -> training/fused_model/ (MLX/HF-layout safetensors).
# Step 2 (convert): attempt mlx_lm.fuse --export-gguf. EXPECTED result on this
#                 kit: NotImplementedError - mlx_lm's GGUF exporter supports
#                 neither quantized (4-bit) source weights nor the
#                 granitemoehybrid architecture (llama/mixtral/mistral only).
#                 The working conversion path is documented in
#                 README_TRAINING.md / REMOTE_RECIPE.md: fuse the adapter into
#                 the ORIGINAL fp16/bf16 HF checkpoint off-site, then run
#                 llama.cpp convert_hf_to_gguf.py + llama-quantize (Q4_K_M).
#                 That needs ~13 GB scratch, which fails this host's disk gate.
# Exit code reflects step 1 only; step 2's outcome is recorded in the log.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/.venv/bin/python"
LOG="$HERE/logs/fuse_convert.log"
mkdir -p "$HERE/logs"
cd "$HERE"

{
  echo "== fuse_and_convert run $(date -u +%Y-%m-%dT%H:%M:%SZ) =="
  echo "-- step 1: merge adapter into base weights (mlx_lm.fuse) --"
  "$PY" -m mlx_lm fuse --model base_model --adapter-path adapters \
        --save-path fused_model
  echo "FUSE_RESULT: OK (fused_model/ written)"

  echo "-- step 2: attempt GGUF export (expected: unsupported for quantized granitemoehybrid) --"
  if "$PY" -m mlx_lm fuse --model base_model --adapter-path adapters \
        --save-path fused_model_gguf_attempt --export-gguf \
        --gguf-path model-f16.gguf 2>&1; then
    echo "GGUF_EXPORT_RESULT: OK"
  else
    echo "GGUF_EXPORT_RESULT: UNSUPPORTED_LOCALLY (as documented: quantized weights and/or granitemoehybrid arch not supported by mlx_lm gguf exporter; use off-site fp16 fuse + llama.cpp convert_hf_to_gguf.py per REMOTE_RECIPE.md)"
  fi
} 2>&1 | tee "$LOG"
