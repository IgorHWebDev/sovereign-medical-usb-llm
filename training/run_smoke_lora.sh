#!/bin/bash
# run_smoke_lora.sh - local smoke LoRA (feasibility branch (a)) for m12.
# QLoRA on the stick default granite-4.0-h-micro (4-bit MLX weights) with
# mlx-lm on Apple Silicon. Produces training/adapters/adapters.safetensors
# and training/logs/smoke_train.log with per-step "Iter N: Train loss ..."
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/.venv/bin/python"
[ -x "$PY" ] || { echo "ERROR: venv missing - create with: python3.12 -m venv $HERE/.venv && $HERE/.venv/bin/pip install -r $HERE/requirements.txt"; exit 1; }
[ -f "$HERE/base_model/model.safetensors" ] || { echo "ERROR: base model missing under $HERE/base_model (see TRAINING.json baseModel pin)"; exit 1; }

mkdir -p "$HERE/logs"
cd "$HERE"

echo "== step 1/2: dataset prep (DATASETS.json sft corpus -> chat JSONL) =="
"$PY" prep_dataset.py --n-train 48 --n-valid 8 --out data

echo "== step 2/2: LoRA smoke training (mlx_lm.lora) =="
"$PY" -m mlx_lm lora -c train_config.yaml 2>&1 | tee "$HERE/logs/smoke_train.log"

echo "== done =="
ls -la "$HERE/adapters"
