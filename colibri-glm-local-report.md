# colibrì — Report on Running GLM‑5.2 Locally

**Source scanned:** https://github.com/JustVugg/colibri (cloned + inspected at engine-source
level, not just the README). Findings below are grounded in the actual code, primarily
`c/glm.c` and `c/resource_plan.py`.
**Date of scan:** 2026-07-14

---

## 1. What colibrì actually is (verified against source)

- **A single-file C inference engine.** `c/glm.c` = 3,912 lines, plus small headers
  (`st.h`, `tok.h`, `json.h`, `grammar.h`, `compat.h`, `tier.h`). **Zero runtime
  dependencies** — no BLAS, no Python, no GPU required at inference time.
- **Python is one-time only.** It appears solely in (a) the offline FP8→int4 weight
  converter (`c/tools/convert_fp8_to_int4.py`) and (b) the optional OpenAI-compatible HTTP
  gateway (`c/openai_server.py`, Python **stdlib only**). The engine at runtime is pure C.
- **The core trick (MoE streaming):** GLM‑5.2 is a 744B-parameter Mixture-of-Experts model,
  but only ~40B params are active per token, and only ~11 GB of those change token-to-token.
  So colibrì:
  - keeps the **dense part** (attention, shared experts, embeddings — ~17B params) **resident
    in RAM at int4 (~9.9 GB)**;
  - streams the **21,504 routed experts** (~370 GB on disk at int4, ~19 MB each) **on demand**,
    with a per-layer LRU cache + optional pinned hot-store + OS page cache as a free L2.
- **Platforms:** Linux / WSL2, macOS (opt-in Metal backend), and **native Windows 11** via
  MinGW-w64 (POSIX shim in `c/compat.h`).
- **License:** Apache-2.0 (engine); GLM‑5.2 weights are MIT (Z.ai).

---

## 2. Hard requirements to run (from `resource_plan.py::build_plan`)

The placement planner computes memory exactly like this:

```
expert_cache_bytes = RAM_budget − dense_bytes(~9.9 GB) − runtime_bytes(~4–6 GB)
cap_per_layer      = expert_cache_bytes ÷ per_layer_expert_bytes
```
where `runtime_bytes = 1.2 GB + 2.5 GB + 64·typical_expert + kv_bytes + kv_buffer`.

Three non-negotiable requirements:

1. **Disk: ~370–400 GB free on a LOCAL NVMe SSD.** The int4 model is ~370 GB. The code
   explicitly requires a local `ext4`/`NTFS` path and warns against network/9p mounts. You can
   either convert from the 756 GB FP8 checkpoint shard-by-shard (never needs all 756 GB at
   once, resumable) or download the pre-converted int4 model from Hugging Face.
2. **RAM: ≥16 GB is a HARD floor, and 16 GB is barely usable.** The dense weights (~9.9 GB) +
   runtime buffers (~5 GB) must stay resident. At 16 GB the leftover expert cache shrinks to
   ~1–2 experts/layer, so every token misses to disk. The planner emits the warning
   *"RAM budget cannot hold one expert slot per sparse layer"* in this regime. The RAM budget
   defaults to 88% of available memory, with an 8 GB floor.
3. **Modern x86-64 CPU with AVX2.** AVX-512 / VNNI is a large multiplier but not required.
   **No GPU needed** (optional CUDA/Metal tiers exist but earn their keep only when the CPU is
   the weak link).

---

## 3. Speed reality (community-measured; consistent with the code's memory model)

| Machine class | Measured / expected decode |
|---|---|
| 16–25 GB RAM, ~1 GB/s disk (dev baseline) | **0.05–0.11 tok/s** — ~10–20 s per word |
| Native Windows 11, i5‑12600K, 32 GB (datapoint #113) | **0.08 tok/s** cold |
| Native Windows 11, Core Ultra 9, 32 GB, warmed | **0.03 → 0.5 tok/s** after ~7-prompt warmup |
| Apple M5 Max, 128 GB unified, Metal | **~1.1–2.1 tok/s** |
| 128 GB RAM + PCIe4/5 NVMe (hot experts cached) | **~1–4 tok/s** |
| 128 GB + 24–32 cores or AVX‑512/VNNI | **~5–15 tok/s** (interactive) |

- **Bottleneck shifts with hardware:** disk-bound on small RAM → RAM-bandwidth + CPU-matmul
  bound on big RAM. **RAM size is the dominant lever** (a large cache turns cold disk reads
  into free hits).
- **Self-warming:** the engine records routed-expert frequencies (`.coli_usage`) and auto-pins
  the hottest experts on startup — it gets faster the more it is used.
- **MTP speculative decoding (~2× when warm)** requires the **int8** MTP head. The int4-head
  mirror silently gives 0% draft acceptance and never speculates.

---

## 4. How to run it (once suitable hardware exists)

```bash
cd c && ./setup.sh                     # build + self-test (expects "32/32 positions")

# Read-only readiness + placement inspection (never starts inference):
COLI_MODEL=/nvme/glm52_i4 ./coli doctor
COLI_MODEL=/nvme/glm52_i4 ./coli plan

# Interactive chat with automatic RAM/cache/tier sizing:
COLI_MODEL=/nvme/glm52_i4 ./coli chat --auto-tier
```

- **Model download (skips conversion):** use the int8-MTP variant
  `mateogrgic/GLM-5.2-colibri-int4-with-int8-mtp` on Hugging Face. Verify with
  `ls -l <model>/out-mtp-*` — int8 (correct) sizes are `3527131672 / 5366238584 / 1065950496`.
- **Convert from FP8 instead:** `./coli convert --model /nvme/glm52_i4` (needs `python` with
  `torch safetensors huggingface_hub numpy`, and ~400 GB free NVMe; resumable).
- **OpenAI-compatible server:** `COLI_MODEL=... ./coli serve --host 127.0.0.1 --port 8000`
  (one model process, requests queued via a bounded FIFO; text-only).
- **Runtime is fully offline.** Only the one-time conversion/download step needs internet.

---

## 5. Bottom-line assessment (for an offline clinical-appliance context)

- **Not viable on a 4 GB i3, and not viable on a 16 GB / i7 either.** A 16 GB machine clears
  the RAM floor by a hair, so it would *boot* GLM‑5.2 — but at ~0.05–0.1 tok/s and with a
  mandatory ~400 GB NVMe holding the model. That is a demonstration, not a working tool.
- **For a low-RAM clinical endpoint, colibrì is the wrong tool.** A small resident model
  (e.g. a ~2 GB Q4 Granite/Mamba on llama.cpp) is the correct fit for that hardware class.
  Do not point a clinical endpoint at a 744B model.
- **colibrì is a separate machine question.** It becomes a legitimate option only on a
  **128 GB+ RAM workstation with a PCIe4/5 NVMe**, for **non-realtime, fully-offline**
  back-office work (long-form drafting, research, second-opinion generation) where running a
  frontier-class 744B model with zero cloud dependency is the actual goal. On that machine
  expect ~1–4 tok/s, 100% offline (relevant for PHI).

### Decision summary
| Question | Answer |
|---|---|
| Runs fully offline at runtime? | **Yes** (pure C, zero deps; only conversion/download needs internet) |
| Runs on 4 GB i3? | **No** |
| Runs *usefully* on 16 GB i7? | **No** (~0.05–0.1 tok/s, needs ~400 GB NVMe) |
| Minimum for a usable experience? | **~128 GB RAM + PCIe4/5 NVMe**, AVX2 (AVX-512/VNNI ideal) |
| Right for a clinical endpoint? | **No** — use a small resident model instead |
| Right for an offline back-office 744B workstation? | **Yes**, on the right hardware |
