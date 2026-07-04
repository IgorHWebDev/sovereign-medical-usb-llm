#!/usr/bin/env python3
"""m11 - Baseline eval harness for the two shipped GGUFs on a Japanese medical benchmark.

Scores BOTH shipped models (usb_stick/models/*.gguf) on a FIXED, seed-stable subset
of the pinned eval benchmark (DATASETS.json -> role=eval; JMMLU medical MCQA, 4-choice)
by driving the shipped mac-arm64 llama-server at temperature 0.

Per-model API mode follows usb_stick/models/model_meta.json:
  chatTemplateMode=raw  (RWKV-7) -> POST /completion            with User:/Assistant: framing
  chatTemplateMode=chat (Granite)-> POST /v1/chat/completions   (embedded chat template)

Metric: multiple-choice accuracy (exact answer-letter match) + answer-format adherence
(fraction of items where a valid A/B/C/D choice could be parsed from the model output).

Subset is reproducible: rng=Random(SEED); order=sorted(unique ids); rng.shuffle(order);
subset = order[:N]. So N=5 (smoke) is always a prefix-subset of N=50 (baseline).

Usage:
  python3 tests/eval_ja_med.py --n 50 \
      --out-json evals/baseline_results.json --out-md evals/baseline_results.md
  python3 tests/eval_ja_med.py --n 5 --smoke \
      --out-json <tmp>/smoke.json --out-md <tmp>/smoke.md

Exit 0 = harness ran and wrote both result files (model accuracy is the yardstick,
not a pass/fail gate). Exit != 0 = harness/engine failure.
"""
import argparse
import json
import os
import random
import re
import socket
import subprocess
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STICK = os.path.join(ROOT, "usb_stick")
BIN = os.path.join(STICK, "bin", "mac-arm64", "llama-server")
SEED = 42
LETTERS = ["A", "B", "C", "D", "E", "F"]
# full-width A-F -> index
FULLWIDTH = {chr(0xFF21 + i): i for i in range(6)}


def log(*a):
    print(*a, flush=True)


def utc_now():
    return subprocess.run(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"],
                          capture_output=True, text=True).stdout.strip()


def load_eval_dataset():
    dj = json.load(open(os.path.join(ROOT, "DATASETS.json"), encoding="utf-8"))
    evals = [d for d in dj["datasets"] if d.get("role") == "eval"]
    if not evals:
        sys.exit("FAIL: no role=eval dataset in DATASETS.json")
    ds = evals[0]
    path = os.path.join(ROOT, ds["local_path"])
    rows = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return ds, rows


def pick_subset(rows, n):
    by_id = {r["sample_id"]: r for r in rows}
    order = sorted(by_id.keys())
    rng = random.Random(SEED)
    rng.shuffle(order)
    subset_ids = order[:n]
    return subset_ids, [by_id[i] for i in subset_ids]


def load_models():
    meta = json.load(open(os.path.join(STICK, "models", "model_meta.json"),
                          encoding="utf-8"))
    return meta["models"]


def free_port(lo=8090, hi=8099):
    for p in range(lo, hi + 1):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1", p)) != 0:
                return p
    sys.exit("FAIL: no free port in %d-%d" % (lo, hi))


def start_server(model_file, port, logpath):
    fh = open(logpath, "w")
    proc = subprocess.Popen(
        [BIN, "--model", os.path.join("models", model_file),
         "--host", "127.0.0.1", "--port", str(port),
         "--ctx-size", "8192", "--no-mmap"],
        cwd=STICK, stdout=fh, stderr=subprocess.STDOUT)
    url = "http://127.0.0.1:%d/health" % port
    for _ in range(180):
        if proc.poll() is not None:
            fh.close()
            raise RuntimeError("llama-server exited while loading %s (see %s)"
                               % (model_file, logpath))
        try:
            r = urllib.request.urlopen(url, timeout=2)
            if b'"status":"ok"' in r.read():
                return proc, fh
        except Exception:
            pass
        time.sleep(1)
    proc.kill()
    fh.close()
    raise RuntimeError("llama-server not healthy after 180s for %s" % model_file)


def stop_server(proc, fh):
    try:
        proc.terminate()
        for _ in range(15):
            if proc.poll() is not None:
                break
            time.sleep(1)
        if proc.poll() is None:
            proc.kill()
    finally:
        try:
            fh.close()
        except Exception:
            pass


def build_question(row):
    q = row["question"]
    opts = row["options"]
    lines = ["問題: " + q, "", "選択肢:"]
    for i, o in enumerate(opts):
        lines.append("%s. %s" % (LETTERS[i], o))
    return "\n".join(lines), len(opts)


INSTRUCTION = ("あなたは日本語の医療試験を解答する専門家です。"
               "次の多肢選択問題について、選択肢の中から最も適切なものを1つだけ選び、"
               "その記号（A、B、C、D のいずれか1文字）だけを答えてください。"
               "説明や理由は不要です。")


def parse_choice(text, n_options):
    """Return 0-based index of the chosen letter, or None if unparseable."""
    if not text:
        return None
    # normalise full-width letters
    norm = "".join(str(FULLWIDTH.get(c, c)) for c in text)
    # prefer a letter that appears right after a marker like 答え / 正解 / :
    m = re.search(r"(?:答え|正解|answer)[^A-Fａ-ｆ]{0,6}([A-Fa-f])", norm)
    if m:
        idx = LETTERS.index(m.group(1).upper())
        if idx < n_options:
            return idx
    # otherwise first standalone A-F letter
    m = re.search(r"\b([A-Fa-f])\b", norm)
    if m:
        idx = LETTERS.index(m.group(1).upper())
        if idx < n_options:
            return idx
    # any A-F letter at all
    m = re.search(r"([A-Fa-f])", norm)
    if m:
        idx = LETTERS.index(m.group(1).upper())
        if idx < n_options:
            return idx
    # fallback: a digit 1..n
    m = re.search(r"([1-9])", norm)
    if m:
        idx = int(m.group(1)) - 1
        if 0 <= idx < n_options:
            return idx
    return None


def ask(port, mode, question_block, n_options):
    if mode == "raw":
        prompt = ("User: " + INSTRUCTION + "\n\n" + question_block
                  + "\n\nAssistant: 答え:")
        req = {"prompt": prompt, "n_predict": 16, "temperature": 0.0,
               "top_k": 1, "seed": SEED, "cache_prompt": False,
               "stop": ["\n\nUser:", "\nUser:", "User:"]}
        url = "http://127.0.0.1:%d/completion" % port
    else:
        req = {"messages": [{"role": "system", "content": INSTRUCTION},
                            {"role": "user", "content": question_block}],
               "max_tokens": 16, "temperature": 0.0, "top_k": 1,
               "seed": SEED, "stream": False}
        url = "http://127.0.0.1:%d/v1/chat/completions" % port
    r = urllib.request.urlopen(urllib.request.Request(
        url, json.dumps(req).encode(), {"Content-Type": "application/json"}),
        timeout=300)
    d = json.loads(r.read())
    if mode == "raw":
        out = d.get("content", "") or ""
    else:
        out = d["choices"][0]["message"]["content"] or ""
    tm = d.get("timings", {}) or {}
    return out.strip(), tm.get("predicted_per_second"), tm.get("predicted_n")


def eval_model(entry, subset_rows, port):
    model_file = entry["file"]
    mode = entry["chatTemplateMode"]
    logpath = os.path.join(WORK, "eval_%s.log"
                           % re.sub(r"[^A-Za-z0-9]", "_", model_file))
    log("=== eval: %s (mode=%s, %s, %s) on port %d ===" %
        (model_file, mode, entry["arch"], entry["params"], port))
    proc, fh = start_server(model_file, port, logpath)
    items = []
    correct = 0
    parsed = 0
    tok_rates = []
    tok_total = 0
    t0 = time.time()
    try:
        for row in subset_rows:
            qblock, n_opt = build_question(row)
            gold = row["answer_idx"]
            try:
                out, tps, ntok = ask(port, mode, qblock, n_opt)
                err = ""
            except Exception as e:
                out, tps, ntok, err = "", None, None, "%s: %s" % (type(e).__name__, e)
            choice = parse_choice(out, n_opt)
            ok = (choice == gold)
            if choice is not None:
                parsed += 1
            if ok:
                correct += 1
            if tps:
                tok_rates.append(tps)
            if ntok:
                tok_total += ntok
            items.append({
                "sample_id": row["sample_id"],
                "topic": row.get("metadata", {}).get("topic"),
                "gold_idx": gold,
                "gold_letter": LETTERS[gold],
                "pred_idx": choice,
                "pred_letter": LETTERS[choice] if choice is not None else None,
                "correct": ok,
                "raw_output": out[:200],
                "error": err,
            })
        runtime = round(time.time() - t0, 1)
    finally:
        stop_server(proc, fh)
    n = len(subset_rows)
    avg_tps = round(sum(tok_rates) / len(tok_rates), 2) if tok_rates else None
    result = {
        "model": model_file,
        "arch": entry["arch"],
        "params": entry["params"],
        "role": entry["role"],
        "mode": mode,
        "n_items": n,
        "correct": correct,
        "accuracy": round(correct / n, 4) if n else None,
        "parseable": parsed,
        "format_adherence": round(parsed / n, 4) if n else None,
        "avg_gen_tok_s": avg_tps,
        "gen_tokens_total": tok_total,
        "runtime_s": runtime,
        "items": items,
    }
    log("    %s: accuracy %d/%d = %.1f%%, format %d/%d, %.1f tok/s, %.1fs" %
        (model_file, correct, n, 100 * correct / n if n else 0,
         parsed, n, avg_tps or 0, runtime))
    return result


def write_json(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(payload, open(path, "w", encoding="utf-8"),
              ensure_ascii=False, indent=2)


def write_md(path, payload):
    ds = payload["dataset"]
    L = []
    L.append("# Baseline evaluation — shipped GGUFs on a Japanese medical benchmark (m11)")
    L.append("")
    L.append("Generated: %s" % payload["generated_at"])
    L.append("")
    L.append("Engine: shipped `usb_stick/bin/mac-arm64/llama-server` "
             "(%s), ctx 8192, `--no-mmap`, **temperature 0** (top_k 1, seed %d)."
             % (payload["engine_version"], SEED))
    L.append("")
    L.append("Benchmark: **%s** (`%s`, license %s), role=eval from `DATASETS.json`."
             % (ds["title"], ds["id"], ds["license"]))
    L.append("Task: 4-choice Japanese medical MCQA. "
             "Metric: multiple-choice **accuracy** (exact answer-letter match) plus "
             "**format adherence** (fraction of items yielding a parseable A/B/C/D).")
    L.append("")
    L.append("Fixed subset: **%d items**, seed-stable "
             "(`Random(%d)`-shuffled sorted sample_ids, prefix subset). "
             "Random-guess baseline for 4-choice = 25%%."
             % (payload["subset_size"], SEED))
    if payload.get("smoke"):
        L.append("")
        L.append("> NOTE: this file was produced by a **smoke run** "
                 "(reduced item count) — see `evals/baseline_results.*` for the full baseline.")
    L.append("")
    L.append("## Honest framing (read this before quoting any number)")
    L.append("")
    L.append("These are **2–3B general-purpose, 4-bit-quantized** models (RWKV-7 World "
             "2.9B and IBM Granite-4.0-h-micro ~3B), not medical-tuned large models. "
             "They are **expected to score far below** medical-specialist or "
             "frontier-scale systems on this benchmark, and low scores here are normal "
             "and anticipated. **These numbers are a baseline yardstick for measuring "
             "future fine-tunes (m12+), not a clinical-capability claim.** Nothing here "
             "asserts that either model is safe or accurate for real clinical use; the "
             "stick's clinical value is the offline documentation-drafting workflow with "
             "human review and tamper-evident audit, not benchmark accuracy.")
    L.append("")
    L.append("## Results")
    L.append("")
    L.append("| model | arch | params | mode | items | accuracy | correct | format adherence | avg gen tok/s | runtime (s) |")
    L.append("|---|---|---|---|---|---|---|---|---|---|")
    for r in payload["models"]:
        L.append("| `%s` | %s | %s | %s | %d | **%.1f%%** | %d/%d | %.1f%% | %s | %s |"
                 % (r["model"], r["arch"], r["params"], r["mode"], r["n_items"],
                    100 * (r["accuracy"] or 0), r["correct"], r["n_items"],
                    100 * (r["format_adherence"] or 0),
                    r["avg_gen_tok_s"] if r["avg_gen_tok_s"] is not None else "n/a",
                    r["runtime_s"]))
    L.append("")
    L.append("## Reproducibility")
    L.append("")
    L.append("- Harness: `tests/eval_ja_med.py` (temperature 0, deterministic subset).")
    L.append("- Command: `python3 tests/eval_ja_med.py --n %d --out-json "
             "evals/baseline_results.json --out-md evals/baseline_results.md`"
             % payload["subset_size"])
    L.append("- Dataset file: `%s` (sha256 `%s`)." % (ds["local_path"], ds["sha256"]))
    L.append("- Exact subset `sample_id`s (%d):" % len(payload["subset_ids"]))
    L.append("")
    L.append("```")
    # wrap ids for readability
    ids = payload["subset_ids"]
    for i in range(0, len(ids), 10):
        L.append(" ".join(ids[i:i + 10]))
    L.append("```")
    L.append("")
    L.append("Per-item predictions (gold vs. predicted letter) are in "
             "`%s`." % os.path.basename(payload["_json_path"]))
    L.append("")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8").write("\n".join(L))


def engine_version():
    try:
        out = subprocess.run([BIN, "--version"], capture_output=True, text=True)
        m = re.search(r"version:\s*(\S+)\s*\(([0-9a-f]+)\)",
                      (out.stdout + out.stderr))
        if m:
            return "llama.cpp b%s (%s)" % (m.group(1), m.group(2))
    except Exception:
        pass
    return "llama.cpp (unknown)"


def main():
    global WORK
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=50, help="subset size (>=50 for baseline)")
    ap.add_argument("--out-json", required=True)
    ap.add_argument("--out-md", required=True)
    ap.add_argument("--smoke", action="store_true",
                    help="mark output as a reduced smoke run")
    ap.add_argument("--work", default=os.path.join(ROOT, "tests", "smoke_work"))
    args = ap.parse_args()

    WORK = args.work
    os.makedirs(WORK, exist_ok=True)

    if not (os.path.isfile(BIN) and os.access(BIN, os.X_OK)):
        sys.exit("FAIL: shipped llama-server missing/not executable: %s" % BIN)

    ds, rows = load_eval_dataset()
    subset_ids, subset_rows = pick_subset(rows, args.n)
    models = load_models()
    if len(models) < 2:
        sys.exit("FAIL: expected >=2 models in model_meta.json")

    port = free_port()
    log("Eval subset: %d items (seed %d); models: %s" %
        (len(subset_rows), SEED, ", ".join(m["file"] for m in models)))

    model_results = []
    for entry in models:
        mfile = os.path.join(STICK, "models", entry["file"])
        if not os.path.isfile(mfile):
            sys.exit("FAIL: model file missing: %s" % mfile)
        model_results.append(eval_model(entry, subset_rows, port))

    payload = {
        "schema": "med-usb/eval/baseline/v1",
        "generated_at": utc_now(),
        "engine_version": engine_version(),
        "host": "build Mac (Apple Silicon)",
        "temperature": 0.0,
        "seed": SEED,
        "smoke": bool(args.smoke),
        "subset_size": len(subset_rows),
        "subset_ids": subset_ids,
        "dataset": {
            "id": ds["id"], "title": ds["title"], "license": ds["license"],
            "local_path": ds["local_path"], "sha256": ds["sha256"],
            "records_total": ds.get("records"),
        },
        "models": model_results,
        "_json_path": os.path.abspath(args.out_json),
    }
    write_json(args.out_json, payload)
    write_md(args.out_md, payload)
    log("Wrote %s and %s" % (args.out_json, args.out_md))
    # harness success regardless of model accuracy
    return 0


if __name__ == "__main__":
    sys.exit(main())
