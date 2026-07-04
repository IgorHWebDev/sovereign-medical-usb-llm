# training/ - SFT / LoRA fine-tuning kit (m12)

A complete, reproducible LoRA/SFT kit for the med-USB copilot, plus the
real-hospital production path. The local smoke run (feasibility branch (a))
has already executed on this Apple Silicon host; see `TRAINING.json`.

## What is in here

| File | Purpose |
|---|---|
| `prep_dataset.py` | DATASETS.json `sft` corpus (medqa_jp) -> mlx-lm chat JSONL (`data/train.jsonl`, `data/valid.jsonl`); verifies source sha256. |
| `train_config.yaml` | mlx-lm LoRA config for the stick default (granite-4.0-h-micro, 4-bit MLX / QLoRA). |
| `run_smoke_lora.sh` | One-command local smoke run: prep + `mlx_lm lora`. Writes `adapters/` + `logs/smoke_train.log`. |
| `fuse_and_convert.sh` | Merge adapter into base (`mlx_lm fuse`) and attempt GGUF export (documents the local limitation). |
| `eval_tuned_vs_baseline.py` | 20-item held-out base-vs-tuned comparison -> `evals/tuned_vs_baseline.md`. |
| `requirements.txt` | Fully version-pinned local (Apple Silicon / MLX) deps. |
| `TRAINING.json` | Machine-readable record: framework choice, live arch-support proof, smoke-run metrics, branch taken. |
| `REMOTE_RECIPE.md` | Off-site GPU production recipe (PyTorch QLoRA for granite; RWKV-LM for RWKV-7) + GGUF re-quantization + ship gating. |
| `base_model/` | MLX 4-bit checkpoint of the stick default (sha256-pinned in TRAINING.json). |
| `adapters/`, `fused_model/`, `logs/`, `data/` | Smoke-run outputs. |

## Framework choice

**mlx-lm** (0.31.3) on Apple Silicon. Chosen because the target model
`granite-4.0-h-micro` (arch **granitemoehybrid**, a Mamba-2/Transformer hybrid)
has native mlx-lm support (`mlx_lm/models/granitemoehybrid.py`), verified live
on 2026-07-03 against the ml-explore/mlx-lm repo and the installed wheel. QLoRA
over the 4-bit base keeps peak memory ~9.9 GB, inside this host's 24 GiB.

> transformers is pinned to **4.57.1** (not the >=5.0.0 mlx-lm asks for):
> transformers 5.13.0 breaks the mlx_lm import. See `requirements.txt` note.

## Reproduce the local smoke run

```bash
cd training
python3.12 -m venv .venv
.venv/bin/pip install -r requirements.txt
# base_model/ must contain the MLX checkpoint (see TRAINING.json baseModel pin)
./run_smoke_lora.sh          # >=10 steps on 48 real medqa_jp examples
./fuse_and_convert.sh        # merge adapter; attempt GGUF (expected: unsupported locally)
.venv/bin/python eval_tuned_vs_baseline.py   # 20-item base-vs-tuned proof
```

Result last run: train loss 2.055 -> 0.736, val loss 2.113 -> 1.061 over 15
steps; adapter saved to `adapters/adapters.safetensors`.

## RWKV-7 alternative (stick PRIMARY model)

The stick's **primary** model is RWKV-7 World 2.9B (arch `rwkv7`,
Apache-2.0), a pure non-Transformer (linear-attention) model. It is **not**
fine-tuned with mlx-lm's generic LoRA; the reference path is its **native
trainer, BlinkDL/RWKV-LM** (RWKV-v7 scripts: state-tuning / LoRA / full SFT,
PyTorch + CUDA). Steps: convert the chat JSONL to the RWKV binidx corpus with
`RWKV-LM/RWKV-v5/tools/make_data.py`, train with `train.py --my_testing x070`,
then convert the resulting `.pth` to GGUF via llama.cpp's RWKV converter and
quantize to Q4_K_M. Full commands in `REMOTE_RECIPE.md` section 1B. (mlx-lm
does ship `mlx_lm/models/rwkv7.py`, so an MLX RWKV-7 LoRA is possible too, but
the RWKV-LM recipe is the validated production route.)

## THE REAL HOSPITAL PATH (production, not this smoke run)

This kit proves the **pipeline mechanics** on open, license-clean, no-PHI exam
data (medqa_jp, MIT). It makes **no quality claim** and must **not** ship a
tuned model as-is. The production path, per the FDE proposal:

1. **Gold-set acquisition.** Obtain the hospital fine-tuning corpus through the
   **AI Medical Centre / Data Access Review Committee** governance process.
   No data is used without committee approval.
2. **De-identification first.** SFT runs on **de-identified data ONLY**. Apply
   the de-id pipeline and human review before any data leaves the hospital
   network. (Recall caveat: de-id is imperfect — see the r45 research note;
   treat de-id output as still-sensitive and keep the reviewer in the loop.)
3. **Off-site GPU SFT.** Run the production recipe in `REMOTE_RECIPE.md` on an
   approved off-site GPU over the de-identified gold set. Never train on raw
   PHI; never send raw PHI off-site.
4. **Re-quantize to GGUF.** Merge -> fp16 -> `convert_hf_to_gguf.py` ->
   `llama-quantize Q4_K_M`, using the pinned llama.cpp tag (b9867).
5. **Re-pin in DECISIONS.json.** Add the tuned GGUF with fresh sha256 + byte
   size as a new entry (do not overwrite the audited baseline pins).
6. **Re-run the gates.** Re-run **m7** (macOS end-to-end smoke + Japanese
   bake-off) and **m9** (final package validation + MANIFEST.sha256) against
   the tuned model **before it ships on the stick**. A tuned model that has not
   passed m7 + m9 must not be placed in `usb_stick/models/`.

Audit mandate (r44): every step above is logged; the tuned model's provenance
(dataset hash, recipe, operator, committee approval id) is recorded before it
is allowed on the stick.
