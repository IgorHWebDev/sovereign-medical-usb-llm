#!/usr/bin/env bash
# verify_m11.sh - mechanically re-test the m11 DoD. exit 0 = pass.
#
# 1) Harness tests/eval_ja_med.py exists.
# 2) Baseline result files evals/baseline_results.json + .md exist, parse, and
#    contain per-model entries for BOTH shipped GGUFs, with accuracy/tok/s/runtime
#    and the recorded subset item ids (>=50). The .md carries the honest-framing text.
# 3) LIVE smoke: re-run a 5-item subset through the shipped mac llama-server against
#    BOTH models at temperature 0, and confirm the smoke result files parse and carry
#    entries for both models.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1
fail() { echo "FAIL: $*" >&2; exit 1; }

HARNESS="$ROOT/tests/eval_ja_med.py"
BJSON="$ROOT/evals/baseline_results.json"
BMD="$ROOT/evals/baseline_results.md"
BIN="$ROOT/usb_stick/bin/mac-arm64/llama-server"

command -v python3 >/dev/null 2>&1 || fail "python3 not found"
[ -f "$HARNESS" ] || fail "harness missing: $HARNESS"
[ -x "$BIN" ] || fail "shipped mac llama-server missing/not executable: $BIN"
[ -f "$BJSON" ] || fail "baseline JSON missing: $BJSON"
[ -f "$BMD" ]   || fail "baseline MD missing: $BMD"

echo "[1/3] baseline results parse + both models present + reproducibility fields..."
python3 - "$BJSON" <<'PY' || exit 1
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
models=d.get("models",[])
files={m["model"] for m in models}
need={"rwkv7-2.9B-world-q4_k_m.gguf","granite-4.0-h-micro-Q4_K_M.gguf"}
if not need.issubset(files):
    print("FAIL: baseline JSON missing model entries; have %s"%files,file=sys.stderr); sys.exit(1)
if len(d.get("subset_ids",[]))<50:
    print("FAIL: subset_ids <50 (%d)"%len(d.get("subset_ids",[])),file=sys.stderr); sys.exit(1)
if abs(float(d.get("temperature",-1)))>1e-9:
    print("FAIL: temperature not 0 (%r)"%d.get("temperature"),file=sys.stderr); sys.exit(1)
for m in models:
    for k in ("accuracy","format_adherence","avg_gen_tok_s","runtime_s","n_items","items"):
        if k not in m:
            print("FAIL: model %s missing field %s"%(m["model"],k),file=sys.stderr); sys.exit(1)
    if m["n_items"]<50:
        print("FAIL: model %s n_items<50"%m["model"],file=sys.stderr); sys.exit(1)
    if len(m["items"])!=m["n_items"]:
        print("FAIL: model %s items length mismatch"%m["model"],file=sys.stderr); sys.exit(1)
print("OK: baseline JSON valid; both models present; %d-item reproducible subset"%len(d["subset_ids"]))
PY
[ $? -eq 0 ] || exit 1

# honest-framing text must be present in the MD
grep -q "yardstick" "$BMD" || fail "baseline MD missing honest-framing (yardstick) text"
grep -q "not a clinical-capability claim" "$BMD" || fail "baseline MD missing 'not a clinical-capability claim'"
grep -q "rwkv7-2.9B-world-q4_k_m.gguf" "$BMD" || fail "baseline MD missing RWKV entry"
grep -q "granite-4.0-h-micro-Q4_K_M.gguf" "$BMD" || fail "baseline MD missing Granite entry"
echo "OK: baseline MD carries both models + honest framing"

echo "[2/3] LIVE 5-item smoke through llama-server (both models, temp 0)..."
SMK="$ROOT/tests/smoke_work/m11_verify"
mkdir -p "$SMK"
SJ="$SMK/smoke_results.json"
SM="$SMK/smoke_results.md"
python3 "$HARNESS" --n 5 --smoke --out-json "$SJ" --out-md "$SM" --work "$SMK" \
  || fail "live smoke harness run failed"

echo "[3/3] smoke result files parse + both models present..."
[ -f "$SJ" ] || fail "smoke JSON not written"
[ -f "$SM" ] || fail "smoke MD not written"
python3 - "$SJ" <<'PY' || exit 1
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
files={m["model"] for m in d.get("models",[])}
need={"rwkv7-2.9B-world-q4_k_m.gguf","granite-4.0-h-micro-Q4_K_M.gguf"}
if not need.issubset(files):
    print("FAIL: smoke JSON missing model entries; have %s"%files,file=sys.stderr); sys.exit(1)
if d.get("subset_size")!=5:
    print("FAIL: smoke subset_size != 5 (%r)"%d.get("subset_size"),file=sys.stderr); sys.exit(1)
for m in d["models"]:
    if len(m["items"])!=5:
        print("FAIL: smoke model %s did not run 5 items"%m["model"],file=sys.stderr); sys.exit(1)
print("OK: live smoke ran 5 items x both models; both entries present")
PY
[ $? -eq 0 ] || exit 1
python3 -c "import json,sys;json.load(open(sys.argv[1]))" "$SJ" || fail "smoke JSON unparseable"
grep -q "rwkv7-2.9B-world-q4_k_m.gguf" "$SM" || fail "smoke MD missing RWKV entry"
grep -q "granite-4.0-h-micro-Q4_K_M.gguf" "$SM" || fail "smoke MD missing Granite entry"

echo "ALL CHECKS PASSED (m11)"
exit 0
