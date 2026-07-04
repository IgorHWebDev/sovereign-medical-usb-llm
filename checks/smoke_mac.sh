#!/bin/bash
# checks/smoke_mac.sh — m7 macOS end-to-end smoke test for the med-usb stick.
#
# What it proves (exit 0 = all pass):
#   1. usb_stick/ works from a REAL exFAT volume (hdiutil sparseimage), like the
#      shipped USB stick, launched via the real START_MAC.command.
#   2. Gateway health + model load OK; the discharge-summary case
#      (tests/prompts/discharge_summary_ja.json) POSTed THROUGH auditgw returns
#      non-empty Japanese text with the required section headers (shape only).
#   3. tok/s recorded from llama-server timings.
#   4. Audit chain grew >= 1 entry, `auditgw verify` passes on the live chain,
#      and FAILS on a 1-byte-tampered copy.
#   5. Clean shutdown: no orphan llama-server/auditgw processes; image detaches.
#
# Runs entirely on 127.0.0.1, no network, no admin rights, nothing written
# outside <repo>/tests/smoke_work and the mounted image.

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STICK="$ROOT/usb_stick"
WORK="$ROOT/tests/smoke_work"
# The image + mountpoint MUST live outside ~/Documents: macOS mounts exFAT via
# the sandboxed UserFS/FSKit daemon, which has no TCC access to Documents —
# attaching an exFAT image stored there fails with "no mountable file systems"
# (verified live on this build host; the same 8 GB image in tmp attaches fine).
IMGWORK="${TMPDIR:-/tmp}/medusb_smoke_m7"
mkdir -p "$IMGWORK/mnt" || { echo "SMOKE FAIL: cannot create $IMGWORK" >&2; exit 1; }
IMGWORK="$(cd "$IMGWORK" && pwd -P)"   # canonical: /var->/private/var, no dup slashes
IMG="$IMGWORK/medusb_smoke.sparseimage"
MNT="$IMGWORK/mnt"
CASE="$ROOT/tests/prompts/discharge_summary_ja.json"
PRESETS="$ROOT/src/ui/presets.json"
LAUNCHER_LOG="$WORK/launcher.log"

PASS_N=0
step() { PASS_N=$((PASS_N + 1)); echo "PASS [$PASS_N] $1"; }

LPID=""
UI_PORT=""
CLEANED=0

# PIDs of every process holding files (incl. cwd / binaries) on the mounted
# image. auditgw + its spawned llama-server run with RELATIVE cmdlines and
# cwd on the image, so pgrep -f on the path would miss them — lsof does not.
mnt_pids() { lsof -t -- "$MNT" 2>/dev/null | sort -u; }

cleanup() {
  [ "$CLEANED" = "1" ] && return 0
  CLEANED=1
  # best-effort teardown so a failed run never leaves servers or mounts behind
  if [ -n "$UI_PORT" ]; then
    curl -s -m 3 -X POST "http://127.0.0.1:$UI_PORT/api/shutdown" >/dev/null 2>&1 || true
    sleep 2
  fi
  if [ -n "$LPID" ] && kill -0 "$LPID" 2>/dev/null; then
    kill "$LPID" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$LPID" 2>/dev/null || break
      sleep 1
    done
    kill -9 "$LPID" 2>/dev/null || true
  fi
  if /sbin/mount | grep -qF " $MNT "; then
    P="$(mnt_pids)"
    [ -n "$P" ] && { kill $P 2>/dev/null; sleep 2; kill -9 $P 2>/dev/null; } || true
    hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach -force "$MNT" >/dev/null 2>&1 || true
  fi
}
fail() {
  echo "SMOKE FAIL: $1" >&2
  [ -f "$LAUNCHER_LOG" ] && { echo "--- launcher.log (tail) ---" >&2; tail -n 30 "$LAUNCHER_LOG" >&2; }
  [ -f "$MNT/audit/gateway-mac.log" ] && { echo "--- gateway log (tail) ---" >&2; tail -n 30 "$MNT/audit/gateway-mac.log" >&2; }
  cleanup
  exit 1
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------- 0) preflight
[ "$(uname -s)" = "Darwin" ] || fail "this smoke test must run on macOS (hdiutil)"
for t in hdiutil rsync python3 curl; do
  command -v "$t" >/dev/null 2>&1 || fail "required tool missing: $t"
done
[ -f "$CASE" ] || fail "test case missing: $CASE"
[ -f "$PRESETS" ] || fail "presets missing: $PRESETS"
[ -x "$STICK/START_MAC.command" ] || fail "usb_stick/START_MAC.command missing"
[ -f "$STICK/bin/mac-arm64/llama-server" ] || fail "mac llama-server missing"
[ -f "$STICK/bin/mac-arm64/auditgw" ] || fail "mac auditgw missing"

AVAIL_GB="$(df -g "${TMPDIR:-/tmp}" | awk 'NR==2 {print $4}')"
[ "${AVAIL_GB:-0}" -ge 6 ] || fail "need >= 6 GB free to build the smoke image (have ${AVAIL_GB} GB)"

mkdir -p "$WORK"
# detach any stale mount from a previous aborted run
if /sbin/mount | grep -qF " $MNT "; then
  hdiutil detach "$MNT" >/dev/null 2>&1 || hdiutil detach -force "$MNT" >/dev/null 2>&1 \
    || fail "stale image mounted at $MNT and cannot detach"
fi
step "preflight: macOS tools, artifacts, ${AVAIL_GB} GB free, no stale mount"

# ------------------------------------------- 1) exFAT sparseimage + rsync copy
hdiutil create -ov -quiet -size 8g -fs ExFAT -volname MEDUSBSMOKE \
  -type SPARSE -layout MBRSPUD "$IMG" || fail "hdiutil create (exFAT sparseimage)"
hdiutil attach -quiet -nobrowse -mountpoint "$MNT" "$IMG" || fail "hdiutil attach"
/sbin/mount | grep -F " $MNT " | grep -qi exfat || fail "mounted volume is not exFAT"
step "created + attached exFAT sparseimage at $MNT"

rsync -rltD --delete "$STICK"/ "$MNT"/ || fail "rsync usb_stick/ onto the image"
[ -f "$MNT/models/$(sed -n 's/^default_model=//p' "$STICK/stick.config" | head -n1)" ] \
  || fail "default model missing on image after rsync"
step "rsynced usb_stick/ onto the image ($(du -sh "$MNT" 2>/dev/null | awk '{print $1}'))"

# --------------------------------------- 2) launch via the REAL START_MAC.command
# PATH shim: the launcher calls bare `open` to pop a browser; make it a no-op
# so the smoke test stays headless. Everything else is the real launcher.
mkdir -p "$WORK/shim"
printf '#!/bin/sh\nexit 0\n' > "$WORK/shim/open"
chmod +x "$WORK/shim/open"

: > "$LAUNCHER_LOG"
rm -f "$MNT/audit/session-mac.env" 2>/dev/null
PATH="$WORK/shim:$PATH" bash "$MNT/START_MAC.command" </dev/null >"$LAUNCHER_LOG" 2>&1 &
LPID=$!

SESSION_ENV="$MNT/audit/session-mac.env"
for _ in $(seq 1 30); do
  [ -f "$SESSION_ENV" ] && break
  kill -0 "$LPID" 2>/dev/null || fail "launcher exited before writing session-mac.env"
  sleep 1
done
[ -f "$SESSION_ENV" ] || fail "session-mac.env not written within 30s"
UI_PORT="$(sed -n 's/^ui_port=//p' "$SESSION_ENV" | head -n1)"
LLM_PORT="$(sed -n 's/^llm_port=//p' "$SESSION_ENV" | head -n1)"
[ -n "$UI_PORT" ] && [ -n "$LLM_PORT" ] || fail "ports missing from session-mac.env"
step "launched from the image via real START_MAC.command (pid $LPID, ui=$UI_PORT, llm=$LLM_PORT)"

# ------------------------------------------------------- 3) health: gw + model
GW_UP=0
for _ in $(seq 1 120); do
  if curl -s -m 2 "http://127.0.0.1:$UI_PORT/api/status" 2>/dev/null | grep -q '"ok":true'; then
    GW_UP=1; break
  fi
  kill -0 "$LPID" 2>/dev/null || fail "launcher died while waiting for the gateway"
  sleep 1
done
[ "$GW_UP" = "1" ] || fail "gateway /api/status not OK within 120s"

LLM_UP=0
for _ in $(seq 1 300); do
  if curl -s -m 2 "http://127.0.0.1:$UI_PORT/api/status" 2>/dev/null | grep -q '"llm_reachable":true'; then
    LLM_UP=1; break
  fi
  sleep 1
done
[ "$LLM_UP" = "1" ] || fail "model not reachable through auditgw within 300s"
step "health OK: gateway up, llama-server loaded the model (through /api/status)"

status_seq() {
  curl -s -m 5 "http://127.0.0.1:$UI_PORT/api/status" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["audit_last_seq"])'
}
SEQ_BEFORE="$(status_seq)" || fail "cannot read audit_last_seq"

# ------------------------------- 4) operator gate: no X-Operator-Id must be 401
NOAUTH_CODE="$(curl -s -m 30 -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' -d '{"prompt":"x","n_predict":1}' \
  "http://127.0.0.1:$UI_PORT/completion")"
[ "$NOAUTH_CODE" = "401" ] || fail "inference without X-Operator-Id returned $NOAUTH_CODE, want 401"
step "operator gate: request without X-Operator-Id rejected with 401"

# ------------------- 5) discharge-summary case through auditgw + shape asserts
UI_PORT="$UI_PORT" CASE="$CASE" PRESETS="$PRESETS" WORK="$WORK" python3 - <<'PYEOF' || fail "discharge-summary inference/assertions failed"
import json, os, re, sys, urllib.request

case    = json.load(open(os.environ["CASE"]))
presets = {p["id"]: p for p in json.load(open(os.environ["PRESETS"]))["presets"]}
sysp    = presets[case["preset"]]["system_prompt"]
ui      = os.environ["UI_PORT"]

gen = dict(case["generation"])
prompt = "User: " + sysp + "\n\n" + case["input_text_ja"] + "\n\nAssistant:"
req = {"prompt": prompt, "cache_prompt": False}
req.update(gen)

r = urllib.request.urlopen(urllib.request.Request(
    f"http://127.0.0.1:{ui}/completion", json.dumps(req).encode(),
    {"Content-Type": "application/json", "X-Operator-Id": "smoke-m7"}), timeout=600)
d = json.loads(r.read())
out = (d.get("content") or "").strip()
tm = d.get("timings", {})
toks = tm.get("predicted_per_second")

problems = []
if len(out) < case["min_output_chars"]:
    problems.append(f"output too short: {len(out)} < {case['min_output_chars']}")
if case.get("assert_japanese") and not re.search(r"[぀-ヿ一-鿿]", out):
    problems.append("output contains no Japanese characters")
missing_req = [s for s in case["required_sections"] if s not in out]
if missing_req:
    problems.append(f"missing required section headers: {missing_req}")
present = [s for s in case["all_sections"] if s in out]
if len(present) < case["min_sections_present"]:
    problems.append(f"only {len(present)}/{len(case['all_sections'])} section headers present, "
                    f"need >= {case['min_sections_present']}")
if toks is None:
    problems.append("no timings.predicted_per_second in response")

work = os.environ["WORK"]
open(f"{work}/smoke_output_ja.txt", "w").write(out + "\n")
json.dump({"tok_s": toks, "prompt_tok_s": tm.get("prompt_per_second"),
           "predicted_n": tm.get("predicted_n"), "chars": len(out),
           "sections_present": present, "problems": problems},
          open(f"{work}/smoke_metrics.json", "w"), ensure_ascii=False, indent=2)

print(f"  output: {len(out)} chars, sections {len(present)}/{len(case['all_sections'])} "
      f"(required {len(case['required_sections'])-len(missing_req)}/{len(case['required_sections'])})")
print(f"  TOKENS_PER_SEC={round(toks,1) if toks else 'n/a'} "
      f"(prompt {round(tm.get('prompt_per_second',0),1)} tok/s, {tm.get('predicted_n')} tokens)")
for p in problems:
    print("  ASSERT FAIL: " + p, file=sys.stderr)
sys.exit(1 if problems else 0)
PYEOF
TOKS="$(python3 -c 'import json;print(round(json.load(open("'"$WORK"'/smoke_metrics.json"))["tok_s"],1))')"
step "discharge summary via auditgw: non-empty Japanese output with required headers, ${TOKS} tok/s (see tests/smoke_work/smoke_output_ja.txt)"

# ----------------------------------------------- 6) audit chain grew + verifies
SEQ_AFTER="$(status_seq)" || fail "cannot re-read audit_last_seq"
[ "$SEQ_AFTER" -ge "$((SEQ_BEFORE + 1))" ] \
  || fail "audit chain did not grow (before=$SEQ_BEFORE after=$SEQ_AFTER)"

AUDIT_FILE="$MNT/audit/audit-$(date -u +%Y%m).jsonl"
[ -f "$AUDIT_FILE" ] || fail "audit chain file missing on image: $AUDIT_FILE"
"$MNT/bin/mac-arm64/auditgw" verify "$AUDIT_FILE" || fail "auditgw verify failed on the live chain"
step "audit chain grew (seq $SEQ_BEFORE -> $SEQ_AFTER) and auditgw verify passes"

# --------------------------------------------------- 7) tamper-evidence check
TAMPERED="$WORK/tampered_chain.jsonl"
cp "$AUDIT_FILE" "$TAMPERED" || fail "cannot copy chain for tamper test"
python3 - "$TAMPERED" <<'PYEOF' || fail "tamper flip failed"
import sys
p = sys.argv[1]
b = bytearray(open(p, "rb").read())
i = len(b) // 2
while b[i] in (0x0a, 0x0d):  # do not flip a newline: keep JSONL line structure
    i += 1
b[i] ^= 0x01
open(p, "wb").write(bytes(b))
PYEOF
if "$MNT/bin/mac-arm64/auditgw" verify "$TAMPERED" >/dev/null 2>&1; then
  fail "auditgw verify PASSED on a tampered copy (must fail)"
fi
step "tamper test: 1 flipped byte in a copy -> auditgw verify fails"

# ------------------------------------------------------------ 8) clean shutdown
curl -s -m 5 -X POST "http://127.0.0.1:$UI_PORT/api/shutdown" >/dev/null 2>&1 \
  || fail "POST /api/shutdown failed"
SHUT=0
for _ in $(seq 1 30); do
  if ! kill -0 "$LPID" 2>/dev/null; then SHUT=1; break; fi
  sleep 1
done
if [ "$SHUT" != "1" ]; then
  kill "$LPID" 2>/dev/null || true   # launcher trap does its own cleanup
  for _ in $(seq 1 15); do kill -0 "$LPID" 2>/dev/null || { SHUT=1; break; }; sleep 1; done
fi
[ "$SHUT" = "1" ] || fail "launcher did not exit after /api/shutdown"

# orphan check 1: nothing still holds files/cwd on the image (catches the
# relative-cmdline auditgw + llama-server that pgrep -f would miss)
ORPHANS=""
for _ in 1 2 3 4 5; do
  ORPHANS="$(mnt_pids)"
  [ -z "$ORPHANS" ] && break
  sleep 1
done
if [ -n "$ORPHANS" ]; then
  ps -o pid,command -p $ORPHANS >&2 || true
  fail "orphan processes still hold the image after shutdown: $ORPHANS"
fi
# orphan check 2: both service ports are actually free again
port_in_use() { ( exec 3<>"/dev/tcp/127.0.0.1/$1" ) 2>/dev/null; }
port_in_use "$UI_PORT"  && fail "something still listens on ui port $UI_PORT after shutdown"
port_in_use "$LLM_PORT" && fail "something still listens on llm port $LLM_PORT after shutdown"
LPID=""
step "clean shutdown: launcher exited, no orphan llama-server/auditgw processes, ports freed"

# session-end audit event must keep the chain valid
"$STICK/bin/mac-arm64/auditgw" verify "$AUDIT_FILE" >/dev/null 2>&1 \
  || fail "chain invalid after session-end append"
step "chain still verifies after the launcher's session-end audit event"

# ----------------------------------------------------------------- 9) detach
DETACHED=0
for _ in 1 2 3 4 5 6; do
  if hdiutil detach "$MNT" >/dev/null 2>&1; then DETACHED=1; break; fi
  sleep 2   # transient holders like Spotlight indexing get a few retries
done
if [ "$DETACHED" != "1" ]; then
  hdiutil detach -force "$MNT" >/dev/null 2>&1 || true
  fail "image did not detach cleanly (orphan checks passed, but a non-forced detach must succeed)"
fi
rm -f "$IMG"   # reclaim ~4 GB; the image is rebuilt on every run
step "image detached and removed"

echo ""
echo "SMOKE OK: $PASS_N/$PASS_N steps passed, generation ${TOKS} tok/s"
echo "  output : tests/smoke_work/smoke_output_ja.txt"
echo "  metrics: tests/smoke_work/smoke_metrics.json"
exit 0
