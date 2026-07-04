#!/usr/bin/env python3
"""prep_dataset.py - DATASETS.json SFT corpus -> chat-format JSONL for mlx-lm LoRA.

Reads the role=="sft" dataset pinned in <repo>/DATASETS.json (medqa_jp:
Japanese USMLE-style clinical-vignette MCQA, MIT license, no PHI), verifies
its sha256 against the pinned value, and emits mlx-lm chat-format JSONL:

    {"messages": [{"role": "system", ...}, {"role": "user", ...},
                  {"role": "assistant", ...}]}

Split discipline (deterministic, disjoint):
  * train.jsonl / valid.jsonl take the FIRST n_train + n_valid rows (in file
    order) that pass the length filter.
  * eval_tuned_vs_baseline.py takes its held-out items from the END of the
    file, so eval items can never overlap the training split.

Usage:
    python prep_dataset.py [--n-train 48] [--n-valid 8] [--out data]
                           [--max-question-chars 700] [--no-verify]
"""

import argparse
import hashlib
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]

SYSTEM_PROMPT = (
    "あなたは日本の医療従事者を支援する医療文書AIアシスタントです。"
    "臨床の選択肢問題には、正しい選択肢を一つ選んで簡潔に日本語で答えてください。"
)

LETTERS = "ABCDEFGHIJ"


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load_sft_pin() -> dict:
    ds = json.loads((REPO_ROOT / "DATASETS.json").read_text(encoding="utf-8"))
    for entry in ds["datasets"]:
        if entry.get("role") == "sft":
            return entry
    raise SystemExit("ERROR: no role=='sft' dataset pinned in DATASETS.json")


def row_ok(row: dict, max_q: int) -> bool:
    if not row.get("question") or not row.get("options"):
        return False
    if row.get("answer_idx") is None:
        return False
    if not (0 <= int(row["answer_idx"]) < len(row["options"])):
        return False
    if len(row["question"]) > max_q:
        return False
    return True


def to_messages(row: dict) -> dict:
    options = row["options"]
    idx = int(row["answer_idx"])
    lettered = "\n".join(f"{LETTERS[i]}. {opt}" for i, opt in enumerate(options))
    user = (
        f"{row['question']}\n\n選択肢:\n{lettered}\n\n"
        "最も適切な選択肢を一つ選び、「正解はX. …です。」の形式で答えてください。"
    )
    assistant = f"正解は{LETTERS[idx]}. {options[idx]}です。"
    return {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user},
            {"role": "assistant", "content": assistant},
        ]
    }


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n-train", type=int, default=48)
    ap.add_argument("--n-valid", type=int, default=8)
    ap.add_argument("--out", default=str(Path(__file__).resolve().parent / "data"))
    ap.add_argument("--max-question-chars", type=int, default=700)
    ap.add_argument("--no-verify", action="store_true",
                    help="skip sha256 verification of the source corpus")
    args = ap.parse_args()

    pin = load_sft_pin()
    src = REPO_ROOT / pin["local_path"]
    if not src.is_file():
        raise SystemExit(f"ERROR: SFT corpus missing: {src}")

    if not args.no_verify:
        got = sha256_of(src)
        if got != pin["sha256"]:
            raise SystemExit(
                f"ERROR: sha256 mismatch for {src}\n  pinned {pin['sha256']}\n  got    {got}"
            )
        print(f"sha256 OK: {src.name} == {got[:16]}...")

    need = args.n_train + args.n_valid
    rows = []
    with src.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            if row_ok(row, args.max_question_chars):
                rows.append(to_messages(row))
            if len(rows) >= need:
                break
    if len(rows) < need:
        raise SystemExit(f"ERROR: only {len(rows)} usable rows, need {need}")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    splits = {
        "train.jsonl": rows[: args.n_train],
        "valid.jsonl": rows[args.n_train: need],
    }
    for name, subset in splits.items():
        p = out / name
        with p.open("w", encoding="utf-8") as f:
            for r in subset:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"wrote {p} ({len(subset)} examples)")

    print(f"source: {pin['title']} | license: {pin['license']} | "
          f"anonymization: {pin['anonymization']}")


if __name__ == "__main__":
    sys.exit(main())
