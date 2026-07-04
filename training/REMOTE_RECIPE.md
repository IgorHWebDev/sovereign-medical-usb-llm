# REMOTE_RECIPE.md - off-site GPU SFT + GGUF re-quantization

This kit ran its smoke LoRA **locally** (feasibility branch (a); see
`TRAINING.json`). This document is the **production** recipe for the real
hospital run on an off-site GPU, and the fallback (branch (b)) recipe should
the local path ever be infeasible on another host. The kit scripts are
portable: `python -m compileall` passes on every `.py` and `requirements.txt`
is fully version-pinned.

> PHI RAIL: only **de-identified** data leaves the hospital, and only after the
> Data Access Review Committee approves. See `README_TRAINING.md`.

## 0. Machine

- 1x NVIDIA GPU, >= 24 GB VRAM (A10G / L4 / A100 / H100). QLoRA on
  granite-4.0-h-micro (~3.2 B params) fits comfortably in 24 GB.
- ~40 GB scratch disk (fp16 base ~7 GB + fused fp16 ~7 GB + GGUF f16 ~7 GB +
  Q4_K_M ~2 GB + venv/cache).
- Linux + CUDA 12.x, Python 3.11 or 3.12.

## 1. Environment

Two supported stacks — pick per target model.

### A. granite-4.0-h-micro (stick default) — PyTorch + PEFT (CUDA)

```bash
python3.12 -m venv .venv && . .venv/bin/venv/activate 2>/dev/null || . .venv/bin/activate
pip install \
  "torch==2.5.1" \
  "transformers==4.57.1" \
  "peft==0.13.2" \
  "trl==0.11.4" \
  "datasets==3.0.1" \
  "accelerate==1.0.1" \
  "bitsandbytes==0.44.1" \
  "sentencepiece==0.2.0"
```

> The local MLX kit (`requirements.txt`) is Apple-Silicon only. On CUDA use the
> PyTorch stack above. `prep_dataset.py` (dataset -> chat JSONL) is
> framework-agnostic and reused unchanged.

### B. RWKV-7 World 2.9B (stick primary) — native RWKV-LM

```bash
git clone https://github.com/BlinkDL/RWKV-LM
pip install "torch==2.5.1" "pytorch-lightning==1.9.5" "deepspeed==0.14.4" ninja wandb
```

Use the `RWKV-v7` training scripts (state-tuning / LoRA / full SFT). Convert
the medqa_jp chat JSONL into the RWKV binidx corpus with
`RWKV-LM/RWKV-v5/tools/make_data.py`, then train with the reference
`train.py --my_testing "x070"` recipe.

## 2. Data prep (same for both, de-identified corpus)

```bash
python prep_dataset.py --n-train 9000 --n-valid 500 --out data
# For the real run, point DATASETS.json's sft entry at the DE-IDENTIFIED
# hospital gold set instead of medqa_jp, re-hash it, and re-run.
```

## 3. Train (granite QLoRA, PyTorch)

```bash
python train_granite_qlora.py \
  --base ibm-granite/granite-4.0-h-micro \
  --data data --out out/granite-medlora \
  --epochs 3 --batch 8 --grad-accum 4 --lr 1e-4 \
  --lora-r 16 --lora-alpha 32 --load-in-4bit
```

`train_granite_qlora.py` is a thin PEFT/TRL `SFTTrainer` wrapper (4-bit
NF4 base, LoRA on q/k/v/o + MLP, `bf16`, cosine schedule). Loss log to
`out/granite-medlora/trainer_state.json`.

## 4. Merge + convert to GGUF (the path that fails locally)

```bash
# 4a. merge LoRA into the fp16 base (NOT the 4-bit weights)
python -c "
from peft import AutoPeftModelForCausalLM
m = AutoPeftModelForCausalLM.from_pretrained('out/granite-medlora', torch_dtype='float16')
m = m.merge_and_unload()
m.save_pretrained('out/granite-merged-fp16')
"
# 4b. HF -> GGUF f16 with llama.cpp (pinned tag b9867, same as the stick engine)
git clone --branch b9867 --depth 1 https://github.com/ggml-org/llama.cpp
python llama.cpp/convert_hf_to_gguf.py out/granite-merged-fp16 \
  --outfile out/granite-medlora-f16.gguf --outtype f16
# 4c. quantize to Q4_K_M (match the stick quant)
cmake -S llama.cpp -B llama.cpp/build && cmake --build llama.cpp/build -j --target llama-quantize
./llama.cpp/build/bin/llama-quantize \
  out/granite-medlora-f16.gguf out/granite-medlora-Q4_K_M.gguf Q4_K_M
```

> Why this cannot run on the local build host:
> `mlx_lm fuse --export-gguf` refuses with
> `Model type granitemoehybrid not supported for GGUF conversion.` and cannot
> export quantized weights, so the working path is the fp16 fuse + llama.cpp
> convert above — which needs ~13 GB scratch. The local host is at ~5 GiB free
> (disk gate), so branch (a) delivered the MLX-side merge (`fused_model/`) as
> proof and defers the GGUF step here.

## 5. Ship gating (do NOT skip)

1. sha256 + byte size the new `*-Q4_K_M.gguf`; add a `tuned` entry to
   `DECISIONS.json` (do not overwrite the pinned baseline).
2. Re-run **m7** (macOS end-to-end smoke + Japanese bake-off) against the tuned
   GGUF.
3. Re-run **m9** (final package validation + MANIFEST.sha256).
4. Only after both pass may the tuned model replace/augment the stick default.
