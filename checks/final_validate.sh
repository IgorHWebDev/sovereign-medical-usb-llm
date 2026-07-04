#!/bin/bash
# final_validate.sh — m9: final package validation + MANIFEST.sha256.
# Exit 0 = pass. Mechanically re-tests the m9 Definition of Done:
#   1. every checks/verify_m*.sh passes
#   2. usb_stick/MANIFEST.sha256 regenerated (every file except MANIFEST itself
#      and audit/*.jsonl) and verifies with shasum -c
#   3. total usb_stick/ size reported and < 28 GB
#   4. grep -r "/Users/" usb_stick/ returns nothing (excluding MANIFEST)
#   5. a fresh genesis audit entry (usb_stick/audit/genesis.jsonl) embeds the
#      manifest hash, and the hash chain verifies via `auditgw verify`
#
# Never deletes anything under usb_stick/: rebuilt files are written to a temp
# name and mv'd over.
set -u
ROOT="/Users/osx/Documents/med_l_llm"
STICK="$ROOT/usb_stick"
FAIL=0
note() { echo "[final_validate] $1"; }
bad()  { echo "[final_validate] FAIL: $1"; FAIL=1; }

[ -d "$STICK" ] || { bad "usb_stick/ missing"; exit 1; }

# ---------------------------------------------------------------- DoD 1:
# every checks/verify_m*.sh passes
note "--- step 1: run all milestone verify scripts ---"
shopt -s nullglob
VSCRIPTS=("$ROOT"/checks/verify_m*.sh)
shopt -u nullglob
if [ "${#VSCRIPTS[@]}" -lt 7 ]; then
  bad "expected at least 7 verify_m*.sh scripts, found ${#VSCRIPTS[@]}"
fi
for vs in "${VSCRIPTS[@]}"; do
  name="$(basename "$vs")"
  if [ ! -x "$vs" ]; then
    bad "$name is not executable"
    continue
  fi
  if bash "$vs" >/tmp/final_validate_"$name".log 2>&1; then
    note "PASS: $name"
  else
    bad "$name exited nonzero (log: /tmp/final_validate_$name.log)"
    tail -5 /tmp/final_validate_"$name".log | sed 's/^/[final_validate]   | /'
  fi
done
[ "$FAIL" -eq 0 ] || { note "aborting: milestone verifies failed"; exit 1; }

# ---------------------------------------------------------------- DoD 2:
# regenerate MANIFEST.sha256 (every file except MANIFEST itself and
# audit/*.jsonl), then verify it
note "--- step 2: regenerate + verify MANIFEST.sha256 ---"
MTMP="$(mktemp /tmp/manifest.XXXXXX)" || { bad "mktemp failed"; exit 1; }
(
  cd "$STICK" || exit 1
  find . -type f ! -name 'MANIFEST.sha256' ! -path './audit/*.jsonl' -print0 \
    | LC_ALL=C sort -z \
    | xargs -0 shasum -a 256
) > "$MTMP" || { bad "manifest generation failed"; exit 1; }
NMAN="$(wc -l < "$MTMP" | tr -d ' ')"
NFS="$(cd "$STICK" && find . -type f ! -name 'MANIFEST.sha256' ! -path './audit/*.jsonl' | wc -l | tr -d ' ')"
if [ "$NMAN" != "$NFS" ] || [ "$NMAN" -lt 10 ]; then
  bad "manifest has $NMAN lines but stick has $NFS eligible files"
  exit 1
fi
mv "$MTMP" "$STICK/MANIFEST.sha256" || { bad "mv manifest into place failed"; exit 1; }
note "MANIFEST.sha256 regenerated: $NMAN files"
if (cd "$STICK" && shasum -a 256 -c MANIFEST.sha256 >/tmp/final_validate_manifest.log 2>&1); then
  note "PASS: shasum -a 256 -c MANIFEST.sha256 ($NMAN files verified)"
else
  bad "manifest verification failed (log: /tmp/final_validate_manifest.log)"
  grep -v ': OK$' /tmp/final_validate_manifest.log | head -5 | sed 's/^/[final_validate]   | /'
fi

# ---------------------------------------------------------------- DoD 3:
# total usb_stick/ size reported and < 28 GB
note "--- step 3: total size ---"
KB="$(du -sk "$STICK" | awk '{print $1}')"
GB="$(awk -v k="$KB" 'BEGIN{printf "%.2f", k/1048576}')"
LIMIT_KB=$((28 * 1024 * 1024))
note "usb_stick/ total size: ${KB} KB (${GB} GB); limit 28 GB"
if [ "$KB" -ge "$LIMIT_KB" ]; then
  bad "usb_stick/ is ${GB} GB, exceeds 28 GB limit"
else
  note "PASS: size under 28 GB"
fi

# ---------------------------------------------------------------- DoD 4:
# no absolute /Users/ paths anywhere on the stick (excluding MANIFEST)
note "--- step 4: no /Users/ paths on the stick ---"
HITS="$(grep -r "/Users/" "$STICK" --exclude=MANIFEST.sha256 2>/dev/null)"
if [ -n "$HITS" ]; then
  bad "found /Users/ references on the stick:"
  echo "$HITS" | head -5 | sed 's/^/[final_validate]   | /'
else
  note "PASS: grep -r /Users/ returned nothing"
fi

# ---------------------------------------------------------------- DoD 5:
# fresh genesis audit entry embedding the manifest hash, chain verifies
note "--- step 5: fresh genesis audit entry ---"
case "$(uname -s)" in
  Darwin) AUDITGW="$STICK/bin/mac-arm64/auditgw" ;;
  *)      AUDITGW="$STICK/bin/mac-arm64/auditgw" ;;
esac
[ -x "$AUDITGW" ] || { bad "auditgw binary missing/not executable: $AUDITGW"; exit 1; }
MHASH="$(shasum -a 256 "$STICK/MANIFEST.sha256" | awk '{print $1}')"
note "manifest hash: $MHASH"
GTMP="$(mktemp /tmp/genesis.XXXXXX)" || { bad "mktemp failed"; exit 1; }
# OpenChain writes a genesis entry (seq 0, prev_hash = 64 zeros) carrying
# --build-id into a new/empty file; the append adds seq 1 referencing it.
if ! "$AUDITGW" append \
      --file "$GTMP" \
      --operator "final-validate" \
      --prompt "MANIFEST.sha256" \
      --response "$MHASH" \
      --params "{\"manifest_sha256\":\"$MHASH\"}" \
      --build-id "manifest:$MHASH" >/tmp/final_validate_genesis.log 2>&1; then
  bad "auditgw append failed (log: /tmp/final_validate_genesis.log)"
  exit 1
fi
mv "$GTMP" "$STICK/audit/genesis.jsonl" || { bad "mv genesis.jsonl into place failed"; exit 1; }
GEN="$STICK/audit/genesis.jsonl"
if "$AUDITGW" verify "$GEN" >/tmp/final_validate_chain.log 2>&1; then
  note "PASS: $("$AUDITGW" verify "$GEN" 2>/dev/null)"
else
  bad "audit chain verification failed (log: /tmp/final_validate_chain.log)"
fi
python3 - "$GEN" "$MHASH" <<'PY' && note "PASS: genesis entry embeds manifest hash" || bad "genesis entry does not embed manifest hash correctly"
import json, sys
path, mhash = sys.argv[1], sys.argv[2]
with open(path) as f:
    first = json.loads(f.readline())
assert first["seq"] == 0, "first entry is not seq 0"
assert first["prev_hash"] == "0" * 64, "genesis prev_hash is not 64 zeros"
params = first["params"]
if isinstance(params, str):
    params = json.loads(params)
assert params.get("genesis") is True, "genesis flag missing"
assert mhash in params.get("stick_build_id", ""), "manifest hash not in stick_build_id"
PY
# The genesis file itself must be excluded from the manifest (audit/*.jsonl),
# otherwise the manifest hash embedded in it would be circular / stale.
if grep -q "audit/genesis.jsonl" "$STICK/MANIFEST.sha256"; then
  bad "audit/genesis.jsonl leaked into MANIFEST.sha256 (circular)"
else
  note "PASS: audit/*.jsonl correctly excluded from manifest"
fi

# ----------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
  note "ALL CHECKS PASSED — usb_stick/ is ${GB} GB, manifest $NMAN files, manifest sha256 $MHASH"
  exit 0
fi
note "ONE OR MORE CHECKS FAILED"
exit 1
