#!/bin/bash
# verify_m3.sh - mechanical re-test of milestone m3 DoD
# Checks (fast; size + recorded-hash comparison, NOT a full re-hash):
#   1. Both GGUFs exist in usb_stick/models/ with exact pinned byte sizes.
#   2. usb_stick/models/model_meta.json exists, parses, and has per-model:
#      file, sha256, params, arch, license, chatTemplateMode (chat|raw).
#   3. Recorded sha256 in model_meta.json matches the pin in DECISIONS.json
#      for the same file (hash equality is checked record-vs-record; the
#      full hash was computed once at build time).
#   4. model_meta.json arch set covers rwkv7 and a mamba2-hybrid entry.
#   5. Live-engine-gate evidence file checks/m3_gate_output.txt exists and
#      contains Japanese (CJK) characters produced by llama-cli at build time.
# Exit 0 = pass, non-zero = fail.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_DIR="$ROOT/usb_stick/models"
META="$MODELS_DIR/model_meta.json"
DECISIONS="$ROOT/DECISIONS.json"
GATE="$ROOT/checks/m3_gate_output.txt"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -f "$DECISIONS" ] || fail "DECISIONS.json missing"
[ -f "$META" ] || fail "model_meta.json missing at $META"
[ -s "$GATE" ] || fail "live engine gate evidence missing/empty at $GATE"

python3 - "$DECISIONS" "$META" "$MODELS_DIR" "$GATE" <<'PYEOF'
import json, os, sys, re

decisions_path, meta_path, models_dir, gate_path = sys.argv[1:5]

with open(decisions_path) as f:
    dec = json.load(f)
with open(meta_path) as f:
    meta = json.load(f)

def die(msg):
    print("FAIL: " + msg, file=sys.stderr)
    sys.exit(1)

models = meta.get("models")
if not isinstance(models, list) or len(models) < 2:
    die("model_meta.json must list >= 2 models")

required = ["file", "sha256", "params", "arch", "license", "chatTemplateMode"]
pin_by_file = {}
for role in ("primary", "fallback"):
    m = dec["models"][role]
    pin_by_file[m["ggufFilename"]] = (m["sha256"].lower(), int(m["sizeBytes"]))

archs = set()
seen_files = set()
for m in models:
    for k in required:
        if k not in m or m[k] in (None, ""):
            die(f"model_meta entry missing field '{k}': {m.get('file','?')}")
    if m["chatTemplateMode"] not in ("chat", "raw"):
        die(f"chatTemplateMode must be chat|raw, got {m['chatTemplateMode']}")
    fname = m["file"]
    seen_files.add(fname)
    archs.add(m["arch"])
    path = os.path.join(models_dir, fname)
    if not os.path.isfile(path):
        die(f"GGUF missing: {path}")
    if fname not in pin_by_file:
        die(f"{fname} not pinned in DECISIONS.json")
    pin_sha, pin_size = pin_by_file[fname]
    actual_size = os.path.getsize(path)
    if actual_size != pin_size:
        die(f"{fname}: size {actual_size} != pinned {pin_size}")
    if m["sha256"].lower() != pin_sha:
        die(f"{fname}: recorded sha256 {m['sha256']} != pinned {pin_sha}")

missing_pins = set(pin_by_file) - seen_files
if missing_pins:
    die(f"pinned model(s) absent from model_meta.json: {sorted(missing_pins)}")

if "rwkv7" not in archs:
    die(f"no rwkv7 arch entry in model_meta.json (archs={sorted(archs)})")
if not any("mamba" in a or "hybrid" in a for a in archs):
    die(f"no mamba2-hybrid arch entry in model_meta.json (archs={sorted(archs)})")

with open(gate_path, encoding="utf-8", errors="replace") as f:
    gate = f.read()
if not re.search(r"[぀-ヿ一-鿿]", gate):
    die("gate output contains no Japanese (kana/kanji) characters")

print("verify_m3: OK")
PYEOF
rc=$?
exit $rc
