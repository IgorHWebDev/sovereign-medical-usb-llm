#!/bin/bash
# verify_m12.sh - mechanically re-test the m12 DoD (fine-tuning kit + smoke/remote).
# exit 0 = pass. Prints which feasibility branch was taken.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
T="$REPO/training"
fail() { echo "FAIL: $1"; exit 1; }
ok() { echo "  ok: $1"; }

echo "== m12 verify: fine-tuning pipeline =="

# ---- DoD 1: kit present ----
for f in prep_dataset.py train_config.yaml run_smoke_lora.sh requirements.txt \
         TRAINING.json README_TRAINING.md REMOTE_RECIPE.md \
         eval_tuned_vs_baseline.py fuse_and_convert.sh; do
  [ -s "$T/$f" ] || fail "missing kit file: training/$f"
done
ok "kit files present"

# TRAINING.json parses + records a framework with live arch-support proof
python3 - "$T/TRAINING.json" <<'PY' || fail "TRAINING.json invalid / missing framework proof"
import json,sys
d=json.load(open(sys.argv[1]))
fw=d["framework"]["choice"]
assert fw in ("mlx-lm","PyTorch-MPS","RWKV-LM"), fw
assert d["framework"].get("archSupportVerifiedLive")
assert d["target"]["architecture"]
assert d.get("feasibilityBranch") in ("a-local-smoke","b-remote-recipe")
print("  ok: TRAINING.json framework=%s branch=%s arch=%s"%(fw,d["feasibilityBranch"],d["target"]["architecture"]))
PY

# requirements pinned (every non-comment line has ==)
python3 - "$T/requirements.txt" <<'PY' || fail "requirements.txt has unpinned deps"
import sys
bad=[]
for ln in open(sys.argv[1]):
    s=ln.strip()
    if not s or s.startswith("#"): continue
    if "==" not in s: bad.append(s)
assert not bad, "unpinned: %r"%bad
print("  ok: requirements.txt fully pinned")
PY

# prep_dataset.py actually derives from the DATASETS.json sft corpus
grep -q 'role.*==.*"sft"\|role") == "sft"\|== "sft"' "$T/prep_dataset.py" || fail "prep_dataset.py does not select the DATASETS.json sft corpus"
ok "prep_dataset.py reads DATASETS.json sft corpus"

# ---- DoD 2: feasibility branch, machine-checkable ----
BRANCH="$(python3 -c "import json;print(json.load(open('$T/TRAINING.json'))['feasibilityBranch'])")"

# both branches: kit scripts must byte-compile
python3 -m compileall -q "$T/prep_dataset.py" "$T/eval_tuned_vs_baseline.py" \
  || fail "python -m compileall failed on kit scripts"
ok "compileall passes on kit scripts"

if [ "$BRANCH" = "a-local-smoke" ]; then
  echo "BRANCH: (a) LOCAL SMOKE LoRA"
  LOG="$T/logs/smoke_train.log"
  ADP="$T/adapters/adapters.safetensors"
  [ -s "$ADP" ] || fail "adapter artifact missing: $ADP"
  ok "adapter artifact present"
  [ -s "$LOG" ] || fail "loss log missing: $LOG"

  # >= 10 optimizer steps with finite, decreasing loss on >= 32 examples
  python3 - "$LOG" "$T/data/train.jsonl" <<'PY' || fail "smoke loss log did not meet DoD (>=10 steps, finite, decreasing, >=32 examples)"
import re,sys,math
log=open(sys.argv[1]).read()
steps=[(int(i),float(l)) for i,l in re.findall(r"Iter (\d+): Train loss ([\d.]+)",log)]
assert len(steps)>=10, "only %d train-loss steps"%len(steps)
losses=[l for _,l in steps]
assert all(math.isfinite(l) for l in losses), "non-finite loss"
assert losses[-1] < losses[0], "loss not decreasing: %.3f -> %.3f"%(losses[0],losses[-1])
n=sum(1 for _ in open(sys.argv[2]))
assert n>=32, "only %d training examples"%n
print("  ok: %d steps, %d examples, loss %.3f -> %.3f (finite, decreasing)"%(len(steps),n,losses[0],losses[-1]))
PY

  # ---- DoD 3: adapter produced -> merge/convert attempted + eval report ----
  [ -s "$T/logs/fuse_convert.log" ] || fail "fuse_convert.log missing (adapter->GGUF path not attempted)"
  grep -q "FUSE_RESULT: OK" "$T/logs/fuse_convert.log" || fail "adapter merge (fuse) did not succeed"
  grep -q "GGUF_EXPORT_RESULT:" "$T/logs/fuse_convert.log" || fail "GGUF export not attempted/recorded"
  ok "adapter->GGUF merge/convert path attempted + recorded"

  EV="$REPO/evals/tuned_vs_baseline.md"
  [ -s "$EV" ] || fail "evals/tuned_vs_baseline.md missing"
  python3 - "$EV" <<'PY' || fail "tuned_vs_baseline.md missing 20-item comparison table"
import re,sys
t=open(sys.argv[1]).read()
rows=re.findall(r"^\| (train_|test_|dev_)?\w+ \| [A-J] \|",t,re.M)
# count per-item rows in the results table (sample_id | gold | ...)
n=len(re.findall(r"^\| \S+ \| [A-J] \| .* \| .* \|",t,re.M))
assert n>=20, "only %d eval rows"%n
assert "baseline" in t and "tuned" in t
print("  ok: tuned_vs_baseline.md has %d item rows"%n)
PY
else
  echo "BRANCH: (b) REMOTE GPU RECIPE"
  [ -s "$T/REMOTE_RECIPE.md" ] || fail "REMOTE_RECIPE.md missing"
  ok "remote recipe present (validated kit; compileall already passed)"
fi

# ---- DoD 4: hospital path documented ----
for kw in "Data Access Review Committee|AI Medical Centre" "de-identified" "GGUF|re-quantize" "DECISIONS.json" "m7" "m9"; do
  grep -Eq "$kw" "$T/README_TRAINING.md" || fail "README_TRAINING.md missing hospital-path element: $kw"
done
ok "README_TRAINING.md documents the real hospital path (gold set, de-id, off-site GPU, re-quant, re-pin, m7+m9 re-gate)"

echo "PASS: m12 (branch=$BRANCH)"
exit 0
