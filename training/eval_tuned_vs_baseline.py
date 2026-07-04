#!/usr/bin/env python3
"""eval_tuned_vs_baseline.py - 20-item pipeline-proof eval: base model vs base+LoRA.

Held-out items are taken from the END of the pinned SFT corpus (medqa_jp
train.jsonl); prep_dataset.py takes its splits from the START, so the sets
are disjoint by construction.

PIPELINE PROOF ONLY. 20 items is far below statistical significance and the
smoke adapter saw ~48 examples for ~15 steps. Real quality claims require the
hospital gold set + off-site GPU SFT (see README_TRAINING.md), then the m7
bake-off and m9 validation re-runs.

Writes: <repo>/evals/tuned_vs_baseline.md
"""

import argparse
import gc
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import mlx.core as mx
from mlx_lm import load, generate
from mlx_lm.sample_utils import make_sampler

from prep_dataset import LETTERS, SYSTEM_PROMPT, load_sft_pin, row_ok

REPO_ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent


def held_out_items(n_items: int, max_q: int):
    pin = load_sft_pin()
    src = REPO_ROOT / pin["local_path"]
    lines = src.read_text(encoding="utf-8").splitlines()
    items = []
    for line in reversed(lines):  # from the END: disjoint from train/valid
        line = line.strip()
        if not line:
            continue
        row = json.loads(line)
        if row_ok(row, max_q):
            items.append(row)
        if len(items) >= n_items:
            break
    if len(items) < n_items:
        raise SystemExit(f"only {len(items)} held-out items available")
    return items


def build_prompt(tokenizer, row):
    options = row["options"]
    lettered = "\n".join(f"{LETTERS[i]}. {o}" for i, o in enumerate(options))
    user = (
        f"{row['question']}\n\n選択肢:\n{lettered}\n\n"
        "最も適切な選択肢を一つ選び、「正解はX. …です。」の形式で答えてください。"
    )
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user", "content": user},
    ]
    return tokenizer.apply_chat_template(
        messages, add_generation_prompt=True, tokenize=False
    )


def extract_letter(text: str, n_options: int):
    valid = LETTERS[:n_options]
    m = re.search(rf"正解は\s*([{valid}])", text)
    if not m:
        m = re.search(rf"\b([{valid}])[.．、:：]", text)
    if not m:
        m = re.search(rf"([{valid}])", text)
    return m.group(1) if m else None


def run_side(name, adapter_path, items, max_tokens):
    model_dir = str(HERE / "base_model")
    print(f"loading {name} (adapter={adapter_path}) ...")
    model, tokenizer = load(model_dir, adapter_path=adapter_path)
    sampler = make_sampler(temp=0.0)  # greedy: deterministic comparison
    outs = []
    for i, row in enumerate(items):
        prompt = build_prompt(tokenizer, row)
        text = generate(model, tokenizer, prompt=prompt,
                        max_tokens=max_tokens, sampler=sampler)
        outs.append(text.strip())
        print(f"  [{name} {i+1}/{len(items)}] {text.strip()[:60]!r}")
    del model
    gc.collect()
    mx.clear_cache()
    return outs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n-items", type=int, default=20)
    ap.add_argument("--max-tokens", type=int, default=60)
    ap.add_argument("--max-question-chars", type=int, default=700)
    ap.add_argument("--adapter-path", default=str(HERE / "adapters"))
    ap.add_argument("--out", default=str(REPO_ROOT / "evals" / "tuned_vs_baseline.md"))
    args = ap.parse_args()

    items = held_out_items(args.n_items, args.max_question_chars)
    baseline_out = run_side("baseline", None, items, args.max_tokens)
    tuned_out = run_side("tuned", args.adapter_path, items, args.max_tokens)

    rows_md = []
    base_correct = tuned_correct = 0
    for row, b, t in zip(items, baseline_out, tuned_out):
        gold = LETTERS[int(row["answer_idx"])]
        n_opt = len(row["options"])
        bl = extract_letter(b, n_opt)
        tl = extract_letter(t, n_opt)
        base_correct += bl == gold
        tuned_correct += tl == gold
        esc = lambda s: s.replace("|", "\\|").replace("\n", " ")[:90]
        rows_md.append(
            f"| {row['sample_id']} | {gold} | {bl or '-'} {'OK' if bl == gold else 'X'} "
            f"| {tl or '-'} {'OK' if tl == gold else 'X'} | {esc(b)} | {esc(t)} |"
        )

    n = len(items)
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    md = f"""# Tuned (base + smoke LoRA adapter) vs baseline - pipeline proof

Generated: {ts}

- Model: mlx-community/granite-4.0-h-micro-4bit (MLX 4-bit weights of the stick
  default ibm-granite/granite-4.0-h-micro, arch `granitemoehybrid`)
- Adapter: `training/adapters/` (smoke QLoRA: rank 8, ~15 steps on 48 medqa_jp
  examples - see `training/logs/smoke_train.log`)
- Eval: {n} held-out medqa_jp items (taken from the END of the corpus; the
  train/valid splits come from the START, so the sets are disjoint), greedy
  decoding (temp=0), max {args.max_tokens} new tokens, answer letter extracted
  by regex.

**This is a pipeline proof only - no quality bar is claimed or required.**
A ~15-step adapter on 48 examples cannot and should not move real accuracy;
real gains need the hospital gold set + off-site GPU SFT, then m7 bake-off +
m9 validation re-runs (see `training/README_TRAINING.md`).

## Summary

| run | correct / {n} | accuracy |
|---|---|---|
| baseline (no adapter) | {base_correct} / {n} | {base_correct / n:.2f} |
| tuned (smoke adapter) | {tuned_correct} / {n} | {tuned_correct / n:.2f} |

## Per-item results

| sample_id | gold | baseline | tuned | baseline output (trunc) | tuned output (trunc) |
|---|---|---|---|---|---|
{chr(10).join(rows_md)}
"""
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(md, encoding="utf-8")
    print(f"wrote {out}  baseline {base_correct}/{n}  tuned {tuned_correct}/{n}")


if __name__ == "__main__":
    main()
