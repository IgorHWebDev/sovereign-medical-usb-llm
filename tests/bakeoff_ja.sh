#!/bin/bash
# tests/bakeoff_ja.sh — m7 Japanese bake-off: all 5 UI presets x both models.
# Runs the shipped mac-arm64 llama-server against each GGUF in usb_stick/models,
# sends one synthetic Japanese case per preset (tests/prompts/bakeoff_cases_ja.json,
# system prompts from src/ui/presets.json), and writes outputs + tok/s to
# tests/bakeoff_results.md so a human can pick default_model in stick.config.
#
# Per-model API mode follows usb_stick/models/model_meta.json:
#   rwkv7  (chatTemplateMode=raw)  -> POST /completion  with "User: ...\n\nAssistant:"
#   granite(chatTemplateMode=chat) -> POST /v1/chat/completions (embedded template)
#
# Exit 0 = bake-off completed and results written (model quality is for the human).

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

STICK="$ROOT/usb_stick"
BIN="$STICK/bin/mac-arm64/llama-server"
RESULTS="$ROOT/tests/bakeoff_results.md"
WORK="$ROOT/tests/smoke_work"
mkdir -p "$WORK"
LLMLOG="$WORK/bakeoff_llm.log"

fail() { echo "BAKEOFF FAIL: $1" >&2; exit 1; }

[ -x "$BIN" ] || fail "$BIN missing or not executable"
[ -f "$ROOT/src/ui/presets.json" ] || fail "src/ui/presets.json missing"
[ -f "$ROOT/tests/prompts/bakeoff_cases_ja.json" ] || fail "bakeoff cases missing"
[ -f "$STICK/models/model_meta.json" ] || fail "model_meta.json missing"
command -v python3 >/dev/null 2>&1 || fail "python3 required"

# --- free-port scan (same /dev/tcp probe as the launcher) ---------------
port_in_use() { ( exec 3<>"/dev/tcp/127.0.0.1/$1" ) 2>/dev/null; }
PORT=""
for p in $(seq 8090 8099); do
  if ! port_in_use "$p"; then PORT="$p"; break; fi
done
[ -n "$PORT" ] || fail "no free port in 8090-8099"

LLM_PID=""
stop_llm() {
  if [ -n "$LLM_PID" ] && kill -0 "$LLM_PID" 2>/dev/null; then
    kill "$LLM_PID" 2>/dev/null
    for _ in $(seq 1 15); do kill -0 "$LLM_PID" 2>/dev/null || break; sleep 1; done
    kill -9 "$LLM_PID" 2>/dev/null || true
  fi
  LLM_PID=""
}
trap stop_llm EXIT INT TERM

start_llm() { # $1 = model filename
  : > "$LLMLOG"
  ( cd "$STICK" && exec bin/mac-arm64/llama-server \
      --model "models/$1" --host 127.0.0.1 --port "$PORT" \
      --ctx-size 8192 --no-mmap ) >>"$LLMLOG" 2>&1 &
  LLM_PID=$!
  for _ in $(seq 1 120); do
    if curl -s -m 2 "http://127.0.0.1:$PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then
      return 0
    fi
    kill -0 "$LLM_PID" 2>/dev/null || fail "llama-server exited while loading $1 (see $LLMLOG)"
    sleep 1
  done
  fail "llama-server not healthy after 120s for $1"
}

# --- run all presets for one model, writing one JSON result file --------
run_model() { # $1 = model file, $2 = mode (raw|chat), $3 = out json
  MODEL_FILE="$1" MODE="$2" OUT="$3" PORT="$PORT" ROOT="$ROOT" python3 - <<'PYEOF' || fail "requests failed for $1"
import json, os, time, urllib.request

root  = os.environ["ROOT"]
port  = os.environ["PORT"]
model = os.environ["MODEL_FILE"]
mode  = os.environ["MODE"]

presets = {p["id"]: p for p in json.load(open(f"{root}/src/ui/presets.json"))["presets"]}
cases   = json.load(open(f"{root}/tests/prompts/bakeoff_cases_ja.json"))["cases"]

# Sampling calibrated in m7: RWKV-7 raw needs temp=1.0/top_p=0.3/presence=0.5
# to avoid repetition loops; instruction-tuned chat models take low temp.
raw_sampling  = {"temperature": 1.0, "top_p": 0.3, "presence_penalty": 0.5, "seed": 42}
chat_sampling = {"temperature": 0.3, "top_p": 0.9, "seed": 42}

results = []
for case in cases:
    pid = case["preset"]
    sysp = presets[pid]["system_prompt"]
    t0 = time.time()
    try:
        if mode == "raw":
            prompt = "User: " + sysp + "\n\n" + case["input_ja"] + "\n\nAssistant:"
            req = {"prompt": prompt, "n_predict": 700,
                   "stop": ["\n\nUser:", "User:"], "cache_prompt": False}
            req.update(raw_sampling)
            url = f"http://127.0.0.1:{port}/completion"
        else:
            req = {"messages": [{"role": "system", "content": sysp},
                                {"role": "user", "content": case["input_ja"]}],
                   "max_tokens": 700, "stream": False}
            req.update(chat_sampling)
            url = f"http://127.0.0.1:{port}/v1/chat/completions"
        r = urllib.request.urlopen(urllib.request.Request(
            url, json.dumps(req).encode(), {"Content-Type": "application/json"}), timeout=600)
        d = json.loads(r.read())
        if mode == "raw":
            out = d.get("content", "")
        else:
            out = d["choices"][0]["message"]["content"] or ""
        tm = d.get("timings", {})
        toks = tm.get("predicted_per_second")
        ptoks = tm.get("prompt_per_second")
        err = ""
    except Exception as e:  # keep going; record the failure per preset
        out, toks, ptoks, err = "", None, None, f"{type(e).__name__}: {e}"
    wall = round(time.time() - t0, 1)
    markers = case.get("expect_markers", [])
    hit = [m for m in markers if m in out]
    has_ja = any("぀" <= c <= "ヿ" or "一" <= c <= "鿿" for c in out)
    results.append({
        "preset": pid, "mode": mode, "error": err,
        "output": out.strip(), "chars": len(out.strip()),
        "japanese": has_ja,
        "markers_expected": markers, "markers_hit": hit,
        "gen_tok_s": round(toks, 1) if toks else None,
        "prompt_tok_s": round(ptoks, 1) if ptoks else None,
        "wall_s": wall,
    })
    print(f"  [{model}] {pid}: {len(hit)}/{len(markers)} markers, "
          f"{results[-1]['gen_tok_s']} tok/s, {wall}s wall"
          + (f"  ERROR {err}" if err else ""))

json.dump({"model": model, "mode": mode, "results": results},
          open(os.environ["OUT"], "w"), ensure_ascii=False, indent=2)
PYEOF
}

# --- model list from model_meta.json -------------------------------------
MODELS_TSV="$(python3 - <<PYEOF
import json
m = json.load(open("$STICK/models/model_meta.json"))
for e in m["models"]:
    print("\t".join([e["file"], e["chatTemplateMode"], e["arch"], e["params"], e["role"]]))
PYEOF
)"
[ -n "$MODELS_TSV" ] || fail "no models in model_meta.json"

RESULT_FILES=()
while IFS=$'\t' read -r MFILE MMODE MARCH MPARAMS MROLE; do
  [ -f "$STICK/models/$MFILE" ] || fail "model file missing: $MFILE"
  echo "=== bake-off: $MFILE (mode=$MMODE, $MARCH, $MPARAMS, $MROLE) on port $PORT ==="
  start_llm "$MFILE"
  OUTJSON="$WORK/bakeoff_$(echo "$MFILE" | tr -c 'A-Za-z0-9' '_').json"
  run_model "$MFILE" "$MMODE" "$OUTJSON"
  RESULT_FILES+=("$OUTJSON")
  stop_llm
done <<< "$MODELS_TSV"

# --- assemble tests/bakeoff_results.md ------------------------------------
RESULTS="$RESULTS" ROOT="$ROOT" python3 - "${RESULT_FILES[@]}" <<'PYEOF' || fail "cannot write results md"
import json, os, subprocess, sys

files = sys.argv[1:]
data = [json.load(open(f)) for f in files]
ts = subprocess.run(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"],
                    capture_output=True, text=True).stdout.strip()

L = []
L.append("# Japanese bake-off results (m7)")
L.append("")
L.append(f"Generated: {ts}  |  Engine: shipped `usb_stick/bin/mac-arm64/llama-server` "
         "(llama.cpp b9867, ctx 8192, --no-mmap)  |  Host: this build Mac (Apple Silicon)")
L.append("")
L.append("All 5 UI presets x both models, one fully synthetic Japanese case each")
L.append("(`tests/prompts/bakeoff_cases_ja.json`; system prompts = `src/ui/presets.json`).")
L.append("Sampling: raw/RWKV = temp 1.0, top_p 0.3, presence 0.5, seed 42; "
         "chat/Granite = temp 0.3, top_p 0.9, seed 42; 700-token cap.")
L.append("")
L.append("## Summary")
L.append("")
L.append("| model | mode | preset | markers hit | JA | chars | gen tok/s | prompt tok/s |")
L.append("|---|---|---|---|---|---|---|---|")
per_model = {}
for d in data:
    stats = per_model.setdefault(d["model"], {"tok": [], "hit": 0, "tot": 0, "full": 0, "n": 0})
    for r in d["results"]:
        hit, tot = len(r["markers_hit"]), len(r["markers_expected"])
        stats["hit"] += hit; stats["tot"] += tot; stats["n"] += 1
        stats["full"] += 1 if hit == tot else 0
        if r["gen_tok_s"]: stats["tok"].append(r["gen_tok_s"])
        L.append(f"| {d['model']} | {r['mode']} | {r['preset']} | {hit}/{tot} "
                 f"| {'yes' if r['japanese'] else 'NO'} | {r['chars']} "
                 f"| {r['gen_tok_s'] or 'n/a'} | {r['prompt_tok_s'] or 'n/a'} |")
L.append("")
L.append("## Recommendation (advisory — human picks default_model in usb_stick/stick.config)")
L.append("")
best = None
for m, s in per_model.items():
    avg = round(sum(s["tok"]) / len(s["tok"]), 1) if s["tok"] else 0
    cov = f"{s['hit']}/{s['tot']}"
    L.append(f"- **{m}** — required section-marker coverage {cov} "
             f"({s['full']}/{s['n']} presets fully covered), avg generation {avg} tok/s.")
    key = (s["hit"] / max(s["tot"], 1), avg)
    if best is None or key > best[0]:
        best = (key, m)
L.append("")
L.append(f"**Suggested default_model: `{best[1]}`** (highest marker coverage, "
         "speed as tie-breaker). This is advisory only: review the raw outputs below "
         "for clinical usability and set `default_model=` in `usb_stick/stick.config`.")
L.append("")
for d in data:
    L.append(f"## Model: {d['model']} (mode={d['mode']})")
    L.append("")
    for r in d["results"]:
        L.append(f"### preset `{r['preset']}` — {len(r['markers_hit'])}/"
                 f"{len(r['markers_expected'])} markers, {r['gen_tok_s'] or 'n/a'} tok/s "
                 f"(wall {r['wall_s']}s)")
        if r["error"]:
            L.append(f"**ERROR:** `{r['error']}`")
        miss = [m for m in r["markers_expected"] if m not in r["markers_hit"]]
        if miss:
            L.append(f"Missing markers: {' '.join(miss)}")
        L.append("")
        L.append("```")
        L.append(r["output"] if r["output"] else "(empty)")
        L.append("```")
        L.append("")
with open(os.environ["RESULTS"], "w") as f:
    f.write("\n".join(L) + "\n")
print(f"wrote {os.environ['RESULTS']}")
PYEOF

echo "BAKEOFF OK: results in $RESULTS"
exit 0
