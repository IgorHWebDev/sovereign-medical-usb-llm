#!/usr/bin/env bash
# verify_m10.sh - mechanically re-test m10 DoD.
# exit 0 = pass. Checks DATASETS.json parses, required fields present,
# files exist and match recorded size + sha256, >=1 eval and >=1 sft entry.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DJ="$ROOT/DATASETS.json"
fail() { echo "FAIL: $*" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || fail "python3 not found"
command -v shasum   >/dev/null 2>&1 || fail "shasum not found"

[ -f "$DJ" ] || fail "DATASETS.json missing at $DJ"

# 1) parses as JSON
python3 -c "import json;json.load(open('$DJ'))" 2>/dev/null || fail "DATASETS.json does not parse"

# 2) structural checks: >=1 eval, >=1 sft, required fields per entry
python3 - "$DJ" <<'PY' || exit 1
import json,sys
dj=json.load(open(sys.argv[1]))
ds=dj.get("datasets",[])
if not isinstance(ds,list) or not ds:
    print("FAIL: no datasets array",file=sys.stderr); sys.exit(1)
roles=[d.get("role") for d in ds]
if roles.count("eval")<1: print("FAIL: need >=1 eval dataset",file=sys.stderr); sys.exit(1)
if roles.count("sft")<1:  print("FAIL: need >=1 sft dataset",file=sys.stderr); sys.exit(1)
req=["url","license","anonymization","sha256","local_path","size_bytes"]
for d in ds:
    for k in req:
        if not d.get(k) and d.get(k)!=0:
            print(f"FAIL: entry {d.get('id')} missing field {k}",file=sys.stderr); sys.exit(1)
    # PHI guard: forbid raw PHI
    a=str(d.get("anonymization","")).lower()
    if "raw phi" in a or ("phi" in a and "no phi" not in a and "no phi" not in a):
        print(f"FAIL: entry {d.get('id')} anonymization suspicious: {a}",file=sys.stderr); sys.exit(1)
print("OK: structure - %d datasets (%d eval, %d sft)"%(len(ds),roles.count("eval"),roles.count("sft")))
PY
[ $? -eq 0 ] || exit 1

# 3) file existence + size + sha256 match
python3 - "$DJ" <<'PY'
import json,sys
dj=json.load(open(sys.argv[1]))
print("\n".join("%s\t%s\t%s"%(d["local_path"],d["size_bytes"],d["sha256"]) for d in dj["datasets"]))
PY

while IFS=$'\t' read -r path size sha; do
  [ -n "$path" ] || continue
  f="$ROOT/$path"
  [ -f "$f" ] || fail "file missing: $f"
  actual_size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f")
  [ "$actual_size" = "$size" ] || fail "$path size mismatch: got $actual_size want $size"
  actual_sha=$(shasum -a 256 "$f" | awk '{print $1}')
  [ "$actual_sha" = "$sha" ] || fail "$path sha256 mismatch: got $actual_sha want $sha"
  echo "OK: $path size=$size sha256 matches"
done < <(python3 - "$DJ" <<'PY'
import json,sys
dj=json.load(open(sys.argv[1]))
for d in dj["datasets"]:
    print("%s\t%s\t%s"%(d["local_path"],d["size_bytes"],d["sha256"]))
PY
)

# 4) each downloaded file must be valid JSONL
while IFS= read -r path; do
  [ -n "$path" ] || continue
  f="$ROOT/$path"
  python3 - "$f" <<'PY' || fail "invalid JSONL: $f"
import json,sys
n=0
for line in open(sys.argv[1],encoding="utf-8"):
    line=line.strip()
    if line:
        json.loads(line); n+=1
if n==0:
    print("empty",file=sys.stderr); sys.exit(1)
print("OK: %s valid JSONL (%d rows)"%(sys.argv[1],n))
PY
done < <(python3 - "$DJ" <<'PY'
import json,sys
dj=json.load(open(sys.argv[1]))
for d in dj["datasets"]:
    print(d["local_path"])
PY
)

echo "ALL CHECKS PASSED (m10)"
exit 0
