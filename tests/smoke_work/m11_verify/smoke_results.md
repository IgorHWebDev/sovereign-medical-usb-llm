# Baseline evaluation — shipped GGUFs on a Japanese medical benchmark (m11)

Generated: 2026-07-03T23:32:06Z

Engine: shipped `usb_stick/bin/mac-arm64/llama-server` (llama.cpp b9867 (152d337fa)), ctx 8192, `--no-mmap`, **temperature 0** (top_k 1, seed 42).

Benchmark: **JMMLU medical subsets (Japanese medical MCQA)** (`eval-jmmlu-medical`, license CC-BY-SA-4.0), role=eval from `DATASETS.json`.
Task: 4-choice Japanese medical MCQA. Metric: multiple-choice **accuracy** (exact answer-letter match) plus **format adherence** (fraction of items yielding a parseable A/B/C/D).

Fixed subset: **5 items**, seed-stable (`Random(42)`-shuffled sorted sample_ids, prefix subset). Random-guess baseline for 4-choice = 25%.

> NOTE: this file was produced by a **smoke run** (reduced item count) — see `evals/baseline_results.*` for the full baseline.

## Honest framing (read this before quoting any number)

These are **2–3B general-purpose, 4-bit-quantized** models (RWKV-7 World 2.9B and IBM Granite-4.0-h-micro ~3B), not medical-tuned large models. They are **expected to score far below** medical-specialist or frontier-scale systems on this benchmark, and low scores here are normal and anticipated. **These numbers are a baseline yardstick for measuring future fine-tunes (m12+), not a clinical-capability claim.** Nothing here asserts that either model is safe or accurate for real clinical use; the stick's clinical value is the offline documentation-drafting workflow with human review and tamper-evident audit, not benchmark accuracy.

## Results

| model | arch | params | mode | items | accuracy | correct | format adherence | avg gen tok/s | runtime (s) |
|---|---|---|---|---|---|---|---|---|---|
| `rwkv7-2.9B-world-q4_k_m.gguf` | rwkv7 | 2.9B | raw | 5 | **0.0%** | 0/5 | 100.0% | 72.65 | 2.6 |
| `granite-4.0-h-micro-Q4_K_M.gguf` | mamba2-hybrid | 3B | chat | 5 | **40.0%** | 2/5 | 100.0% | 114.82 | 1.8 |

## Reproducibility

- Harness: `tests/eval_ja_med.py` (temperature 0, deterministic subset).
- Command: `python3 tests/eval_ja_med.py --n 5 --out-json evals/baseline_results.json --out-md evals/baseline_results.md`
- Dataset file: `datasets/eval/jmmlu_medical_test.jsonl` (sha256 `8274725a2c36c0a371f1950fa8fff83cf6ea0beda4b92e3a0a8d7f6b7aeee3ab`).
- Exact subset `sample_id`s (5):

```
test_709 test_890 test_708 test_1266 test_617
```

Per-item predictions (gold vs. predicted letter) are in `smoke_results.json`.
